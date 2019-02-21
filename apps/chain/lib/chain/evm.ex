defmodule Chain.EVM do
  @moduledoc """
  EVM abscraction. Each EVMs have to implement this abstraction.
  """

  require Logger

  alias Chain.EVM.{Config, Notification}
  alias Storage.AccountStore

  # Amount of ms the server is allowed to spend initializing or it will be terminated
  @timeout Application.get_env(:chain, :kill_timeout, 60_000)

  @typedoc """
  List of EVM lifecircle statuses

  Meanings:

  - `:none` - Did nothing. Initial status
  - `:starting` - Starting chain process (Not operational)
  - `:active` - Fully operational chain
  - `:terminating` - Termination process started (Not operational)
  - `:terminated` - Chain terminated (Not operational)
  - `:snapshot_taking` - EVM is stopping/stoped to make hard snapshot for evm DB. (Not operational)
  - `:snapshot_taken` - EVM took snapshot and now is in starting process (Not operational)
  - `:snapshot_reverting` - EVM stopping/stoped and in process of restoring snapshot (Not operational)
  - `:snapshot_reverted` - EVM restored snapshot and is in starting process (Not operational)
  - `:failed` - Critical error occured
  """
  @type status ::
          :none
          | :starting
          | :active
          | :terminating
          | :terminated
          | :snapshot_taking
          | :snapshot_taken
          | :snapshot_reverting
          | :snapshot_reverted
          | :failed

  @typedoc """
  Task that should be performed.

  Some tasks require chain to be stopped before performing
  like, taking/reverting snapshots, changing initial evm configs.
  such tasks should be set into `State.task` and after evm termination
  system will perform this task and try to start chain again
  """
  @type scheduled_task ::
          nil
          | {:take_snapshot, description :: binary}
          | {:revert_snapshot, Chain.Snapshot.Details.t()}

  @typedoc """
  Default evm action reply message
  """
  @type action_reply ::
          :ok
          | :ignore
          | {:ok, state :: any()}
          | {:noreply, state :: any()}
          | {:reply, reply :: term(), state :: any()}
          | {:error, term()}

  @doc """
  This callback shuold return path to EVM executable file
  """
  @callback executable!() :: binary

  @doc """
  Callback will be called on chain starting process. 
  It should return 2 ports one for http RPC and another one for WS RPC.
  Also method have to reserve this ports using `Chain.PortReserver` module
  so no other processes should be able to use this ports
  """
  @callback get_ports() :: {http_port :: pos_integer(), ws_port :: pos_integer()}

  @doc """
  This callback is called on starting evm instance. Here EVM should be started and validated RPC.
  The argument is configuration for EVM.
  In must return `{:ok, state}`, that `state` will be keept as in `GenServer` and can be
  retrieved in futher functions.
  """
  @callback start(config :: Chain.EVM.Config.t()) :: {:ok, state :: any()} | {:error, term()}

  @doc """
  This callback will be called when system will need to stop EVM.

  **Note:** this function will be called several times and if it wouldn't return
  success after `@max_start_checks` EVM will raise error. Be ready for that.
  """
  @callback stop(config :: Chain.EVM.Config.t(), state :: any()) :: action_reply()

  @doc """
  Callback is called to check if EVM started and responsive
  """
  @callback started?(config :: Chain.EVM.Config.t(), state :: any()) :: boolean()

  @doc """
  Callback will be invoked after EVM started and confirmed it by `started?/2`
  """
  @callback handle_started(config :: Chain.EVM.Config.t(), state :: any()) :: action_reply()

  @doc """
  Handle incomming message from started OS chain process
  """
  @callback handle_msg(msg :: term(), config :: Chain.EVM.Config.t(), state :: any()) ::
              action_reply()

  @doc """
  This callback is called just before the Process goes down. This is a good place for closing connections.
  """
  @callback terminate(id :: Chain.evm_id(), config :: Chain.EVM.Config.t(), state :: any()) ::
              term()

  @doc """
  Load list of initial accounts
  Should return list of initial accounts for chain.
  By default they will be stored into `{db_path}/addresses.json` file in JSON format

  Reply should be in format
  `{:ok, [Chain.EVM.Account.t()]} | {:error, term()}`
  """
  @callback initial_accounts(config :: Chain.EVM.Config.t(), state :: any()) :: action_reply()

  @doc """
  Callback will be called to get exact EVM version
  """
  @callback version() :: binary

  defmacro __using__(_opt) do
    # credo:disable-for-next-line
    quote do
      use GenServer, restart: :transient

      @behaviour Chain.EVM

      require Logger

      alias Chain.EVM.State
      alias Chain.SnapshotManager
      alias Chain.Snapshot.Details, as: SnapshotDetails

      # maximum amount of checks for evm started
      # system checks if evm started every 200ms
      @max_start_checks 30 * 5

      @doc false
      def start_link(%Config{id: nil}), do: {:error, :id_required}

      def start_link(%Config{id: id} = config) do
        GenServer.start_link(__MODULE__, config,
          name: {:via, Registry, {Chain.EVM.Registry, id}},
          timeout: unquote(@timeout)
        )
      end

      @doc false
      def init(%Config{} = config) do
        {http_port, ws_port} = get_ports()
        new_config = %Config{config | http_port: http_port, ws_port: ws_port}
        {:ok, %State{status: :starting, config: new_config}, {:continue, :start_chain}}
      end

      @doc false
      def handle_continue(:start_chain, %State{config: config} = state) do
        case start(config) do
          {:ok, internal_state} ->
            Logger.debug(
              "#{config.id}: Chain initialization finished successfully ! Waiting for JSON-RPC become operational."
            )

            # Schedule started check
            # Operation is async and `status: :active` will be set later
            # See: `handle_info({:check_started, _})`
            check_started(self())

            %Config{notify_pid: pid} = config

            # Add process monitor for handling pid crash
            if pid do
              Process.monitor(pid)
            end

            # Added. finishing
            {:noreply, State.internal_state(state, internal_state)}

          {:error, err} ->
            Logger.error("#{config.id}: on start: #{inspect(err)}")
            {:stop, {:shutdown, :failed_to_start}, State.status(state, :failed, config)}
        end
      end

      @doc false
      def handle_continue(:stop, %State{config: config, internal_state: internal_state} = state) do
        case stop(config, internal_state) do
          {:ok, new_internal_state} ->
            Logger.debug("#{config.id}: Successfully stopped EVM")

            new_state =
              state
              |> State.status(:terminating, config)
              |> State.internal_state(new_internal_state)

            # Stop timeout
            {:noreply, new_state, 60_000}

          {:error, err} ->
            Logger.error("#{config.id}: Failed to stop EVM with error: #{inspect(err)}")
            {:stop, :shutdown, state}
        end
      end

      @doc false
      # method will be called after snapshot for evm was taken and EVM switched to `:snapshot_taken` status.
      # here evm will be started again
      def handle_continue(
            :start_after_task,
            %State{status: status, config: config} = state
          )
          when status in ~w(snapshot_taken snapshot_reverted)a do
        Logger.debug("#{config.id} Starting chain after #{status}")
        # Start chain process
        {:ok, new_internal_state} = start(config)
        # Schedule started check
        # Operation is async and `status: :active` will be set later
        # See: `handle_info({:check_started, _})`
        check_started(self())
        {:noreply, State.internal_state(state, new_internal_state)}
      end

      @doc false
      def handle_info({:DOWN, ref, :process, pid, _}, %State{config: config} = state) do
        Logger.warn("#{config.id} EVM monitoring failed #{inspect(pid)}. Termination in 1 min")
        Process.demonitor(ref)
        {:noreply, state, 60_000}
      end

      @doc false
      def handle_info(:timeout, %State{config: %{id: id}, status: :terminating} = state) do
        Logger.warn("#{id}: EVM didn't stop after a minute !")
        {:noreply, state, {:continue, :stop}}
      end

      @doc false
      def handle_info(:timeout, %State{config: %{id: id}} = state) do
        Logger.warn("#{id}: Monitoring process didn't reconnect. Terminating EVM")
        {:noreply, state, {:continue, :stop}}
      end

      def handle_info({:check_started, retries}, %State{config: config} = state)
          when retries >= @max_start_checks do
        msg = "#{config.id}: Fialed to start EVM. Alive checks failed"

        Logger.error(msg)
        # Have to notify about error to tell our supervisor to restart evm process
        Notification.send(config, config.id, :error, %{message: msg})

        {:stop, {:shutdown, :failed_to_check_started}, State.status(state, :failed, config)}
      end

      @doc false
      def handle_info(
            {:check_started, retries},
            %State{internal_state: internal_state, config: config} = state
          ) do
        Logger.debug("#{config.id}: Check if evm JSON RPC became operational")

        case started?(config, internal_state) do
          true ->
            Logger.debug("#{config.id}: EVM Finally operational !")

            config
            |> handle_started(internal_state)
            # Marking chain as started and operational
            |> handle_action(State.status(state, :active, config))

          false ->
            Logger.debug("#{config.id}: (#{retries}) not operational fully yet...")

            check_started(self(), retries + 1)
            {:noreply, state}
        end
      end

      @doc false
      def handle_info(
            {_pid, :data, :out, msg},
            %State{config: config, internal_state: internal_state} = state
          ) do
        msg
        |> handle_msg(config, internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_info(
            {_, :result, %Porcelain.Result{status: signal}},
            %State{status: :snapshot_taking, task: {:take_snapshot, description}, config: config} =
              state
          ) do
        %Config{id: id, db_path: db_path, type: type} = config
        Logger.debug("#{id}: Chain terminated for taking snapshot with exit status: #{signal}")

        try do
          details =
            db_path
            |> SnapshotManager.make_snapshot!(type)
            |> Map.put(:description, description)

          # Storing all snapshots
          SnapshotManager.store(details)

          Logger.debug("#{id}: Snapshot made, details: #{inspect(details)}")

          new_state =
            state
            |> State.status(:snapshot_taken, config)
            |> State.task(nil)

          Notification.send(config, id, :snapshot_taken, details)

          {:noreply, new_state, {:continue, :start_after_task}}
        rescue
          err ->
            Logger.error("#{id} failed to make snapshot with error #{inspect(err)}")
            {:stop, :failed_take_snapshot, State.status(state, :failed, config)}
        end
      end

      @doc false
      def handle_info(
            {_, :result, %Porcelain.Result{status: signal}},
            %State{
              status: :snapshot_reverting,
              task: {:revert_snapshot, snapshot},
              config: config
            } = state
          ) do
        %Config{id: id, db_path: db_path, type: type} = config
        Logger.debug("#{id}: Chain terminated for reverting snapshot with exit status: #{signal}")

        try do
          :ok = SnapshotManager.restore_snapshot!(snapshot, db_path)
          Logger.debug("#{id}: Snapshot reverted")

          Notification.send(config, id, :snapshot_reverted, snapshot)

          new_state =
            state
            |> State.status(:snapshot_reverted, config)
            |> State.task(nil)

          {:noreply, new_state, {:continue, :start_after_task}}
        rescue
          err ->
            Logger.error(
              "#{id} failed to revert snapshot #{inspect(snapshot)} with error #{inspect(err)}"
            )

            # {:noreply, State.status(state, :failed, config)}
            {:stop, :failed_restore_snapshot, State.status(state, :failed, config)}
        end
      end

      @doc false
      def handle_info(
            {_, :result, %Porcelain.Result{status: signal}},
            %State{status: :terminating, config: config} = state
          ) do
        Logger.debug("#{config.id} catched process exit status #{signal} on evm terminating")

        # Everything is ok, terminating GenServer
        {:stop, :normal, state}
      end

      @doc false
      def handle_info(
            {_, :result, %Porcelain.Result{status: signal}},
            %State{status: status, config: config} = state
          ) do
        Logger.error(
          "#{config.id} Chain failed with exit status: #{inspect(signal)}. Check logs: #{
            Map.get(config, :output, "")
          }"
        )

        Notification.send(config, config.id, :error, %{
          status: signal,
          message: "#{config.id} chain terminated with status #{status}"
        })

        case status do
          :active ->
            {:stop, :chain_failure, state}

          :starting ->
            {:stop, {:shutdown, :failed_to_start}, state}

          _ ->
            {:stop, :unknown_chain_status, state}
        end
      end

      @doc false
      def handle_info(msg, state) do
        Logger.debug("#{state.config.id}: Got msg #{inspect(msg)}")
        {:noreply, state}
      end

      @doc false
      def handle_call(:config, _from, %State{config: config, status: status} = state) do
        res =
          config
          |> Map.from_struct()
          |> Map.put(:status, status)

        {:reply, {:ok, res}, state}
      end

      @doc false
      def handle_call(
            :initial_accounts,
            _from,
            %State{config: config, internal_state: internal_state} = state
          ) do
        config
        |> initial_accounts(internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_call(:details, _from, %State{config: config} = state) do
        case details(config) do
          %Chain.EVM.Process{} = info ->
            {:reply, {:ok, info}, state}

          _ ->
            {:reply, {:error, "could not load details"}, state}
        end
      end

      @doc false
      def handle_call(:lock, _from, %State{status: :active, config: config} = state),
        do: {:reply, :ok, State.locked(state, true, config)}

      @doc false
      def handle_call(:lock, _from, state),
        do: {:reply, {:error, :not_active_status}, state}

      @doc false
      def handle_call(:unlock, _from, %State{locked: true, config: config} = state),
        do: {:reply, :ok, State.locked(state, false, config)}

      @doc false
      def handle_call(:unlock, _from, state),
        do: {:reply, :ok, state}

      @doc false
      def handle_cast({:new_notify_pid, pid}, %State{config: config} = state),
        do: {:noreply, State.config(state, Map.put(config, :notify_pid, pid))}

      @doc false
      def handle_cast(
            {:take_snapshot, description},
            %State{status: :active, locked: false, config: config, internal_state: internal_state} =
              state
          ) do
        Logger.debug("#{config.id} stopping emv before taking snapshot")
        {:ok, new_internal_state} = stop(config, internal_state)

        new_state =
          state
          |> State.status(:snapshot_taking, config)
          |> State.task({:take_snapshot, description})
          |> State.internal_state(new_internal_state)

        {:noreply, new_state}
      end

      @doc false
      def handle_cast({:take_snapshot, _}, state) do
        Logger.error("No way we could take snapshot for non operational or locked evm")
        {:noreply, state}
      end

      @doc false
      def handle_cast(
            {:revert_snapshot, snapshot},
            %State{status: :active, locked: false, config: config, internal_state: internal_state} =
              state
          ) do
        Logger.debug("#{config.id} stopping emv before reverting snapshot")
        {:ok, new_internal_state} = stop(config, internal_state)

        new_state =
          state
          |> State.status(:snapshot_reverting, config)
          |> State.task({:revert_snapshot, snapshot})
          |> State.internal_state(new_internal_state)

        {:noreply, new_state}
      end

      @doc false
      def handle_cast({:revert_snapshot, _}, state) do
        Logger.error("No way we could revert snapshot for non operational or locked evm")
        {:noreply, state}
      end

      @doc false
      def handle_cast(:stop, %State{} = state),
        do: {:noreply, state, {:continue, :stop}}

      @doc false
      def terminate(
            reason,
            %State{config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id} Terminating evm with reason: #{inspect(reason)}")

        # I have to make terminate function with 3 params. otherwise it might override
        # `GenServer.terminate/2`
        terminate(config.id, config, internal_state)

        # We are setting new state and status 
        # because system will send all required notifications
        # and we really don't care about setting updated state somewhere
        state
        |> State.status(:terminated, config)
        |> State.internal_state(internal_state)

        # If exit reason is normal we could send notification that evm stopped
        case reason do
          r when r in ~w(normal shutdown)a ->
            # Clean path for chain after it was terminated
            Config.clean_on_stop(config)
            # Send notification after stop
            Notification.send(config, config.id, :stopped)

          other ->
            Notification.send(config, config.id, :error, %{message: "#{inspect(other)}"})
        end
      end

      ######
      #
      # Default implementation functions for any EVM
      #
      ######

      @impl Chain.EVM
      def get_ports() do
        http_port = Chain.PortReserver.new_unused_port()
        ws_port = Chain.PortReserver.new_unused_port()

        {http_port, ws_port}
      end

      @impl Chain.EVM
      def handle_msg(_str, _config, _state), do: :ignore

      @impl Chain.EVM
      def started?(%Config{id: id, http_port: http_port}, _) do
        Logger.debug("#{id}: Checking if EVM online")

        case JsonRpc.eth_coinbase("http://localhost:#{http_port}") do
          {:ok, <<"0x", _::binary>>} ->
            true

          _ ->
            false
        end
      end

      @impl Chain.EVM
      def handle_started(%Config{notify_pid: nil}, _internal_state), do: :ok

      def handle_started(%Config{id: id} = config, _internal_state) do
        details = details(config)
        Notification.send(config, id, :started, details)
        :ignore
      end

      @impl Chain.EVM
      def initial_accounts(%Config{db_path: db_path}, state),
        do: {:reply, load_accounts(db_path), state}

      @impl Chain.EVM
      def version(), do: "x.x.x"

      ########
      #
      # Private functions for EVM
      #
      ########

      # Get chain details by config
      defp details(%Config{
             id: id,
             db_path: db_path,
             notify_pid: pid,
             http_port: http_port,
             ws_port: ws_port,
             network_id: network_id,
             gas_limit: gas_limit
           }) do
        # Making request using async to not block scheduler
        [{:ok, coinbase}, {:ok, accounts}] =
          [
            # NOTE: here we will use localhost to avoid calling to chain from outside
            Task.async(fn -> JsonRpc.eth_coinbase("http://localhost:#{http_port}") end),
            Task.async(fn -> load_accounts(db_path) end)
          ]
          |> Enum.map(&Task.await/1)

        %Chain.EVM.Process{
          id: id,
          network_id: network_id,
          coinbase: coinbase,
          accounts: accounts,
          gas_limit: gas_limit,
          rpc_url: "http://#{front_url()}:#{http_port}",
          ws_url: "ws://#{front_url()}:#{ws_port}"
        }
      end

      # Internal handler for evm actions
      defp handle_action(reply, %State{config: config} = state) do
        case reply do
          :ok ->
            {:noreply, state}

          :ignore ->
            {:noreply, state}

          {:ok, new_internal_state} ->
            {:noreply, State.internal_state(state, new_internal_state)}

          {:reply, reply, new_internal_state} ->
            {:reply, reply, State.internal_state(state, new_internal_state)}

          {:error, err} ->
            Logger.error(
              "#{get_in(state, [:config, :id])}: action failed with error: #{inspect(err)}"
            )

            # Do we really need to stop ? 
            {:stop, :error, State.status(state, :failed, config)}
        end
      end

      # Send msg to check if evm started
      # Checks when EVM is started in async mode.
      defp check_started(pid, retries \\ 0),
        do: Process.send_after(pid, {:check_started, retries}, 200)

      # Store initial accounts
      # will return given accoutns
      defp store_accounts(accounts, db_path) do
        AccountStore.store(db_path, accounts)
        accounts
      end

      # Load list of initial accoutns from storage
      defp load_accounts(db_path), do: AccountStore.load(db_path)

      # Get front url for chain
      defp front_url(), do: Application.get_env(:chain, :front_url)

      # Allow to override functions
      defoverridable handle_started: 2,
                     get_ports: 0,
                     started?: 2,
                     handle_msg: 3,
                     version: 0
    end
  end

  @doc """
  Child specification for supervising given `Chain.EVM` module
  """
  @spec child_spec(module(), Chain.EVM.Config.t()) :: :supervisor.child_spec()
  def child_spec(module, %Chain.EVM.Config{id: id} = config) do
    %{
      id: id,
      start: {module, :start_link, [config]},
      restart: :transient,
      shutdown: @timeout
    }
  end
end
