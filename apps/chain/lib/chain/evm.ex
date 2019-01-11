defmodule Chain.EVM do
  @moduledoc """
  EVM abscraction. Each EVMs have to implement this abstraction.
  """

  require Logger

  alias Chain.EVM.Config
  alias Chain.EVM.Notification

  # Amount of ms the server is allowed to spend initializing or it will be terminated
  @timeout Application.get_env(:chain, :kill_timeout, 60_000)

  @typedoc """
  List of EVM lifecircle statuses
  Meanings: 
   
  - `:none` - Did nothing. Initial status
  - `:starting` - Starting chain process (Not operational)
  - `:active` - Fully operational chain
  - `:terminating` - Termination process started (Not operational)
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
  @type scheduled_task :: nil | :take_snapshot | {:revert_snapshot, Chain.Snapshot.Details.t()}

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
  Should start mining process for EVM
  """
  @callback start_mine(config :: Chain.EVM.Config.t(), state :: any()) :: action_reply()

  @doc """
  Stop mining process for EVM
  """
  @callback stop_mine(config :: Chain.EVM.Config.t(), state :: any()) :: action_reply()

  @doc """
  Callback will be invoked on internal spanshot.

  Some chains like `ganache` has internal snapshoting functionality
  And this functionality might be used by some tests/scripts. 
  """
  @callback take_internal_snapshot(config :: Chain.EVM.Config.t(), state :: any()) ::
              action_reply()

  @doc """
  Callback will be invoked on reverting internal snapshot by it's id. 

  Working for only chains like `ganache` that has internal snapshots functionality
  """
  @callback revert_internal_snapshot(id :: binary, config :: Chain.EVM.Config.t(), state :: any()) ::
              action_reply()

  @doc """
  This callback is called just before the Process goes down. This is a good place for closing connections.
  """
  @callback terminate(id :: Chain.evm_id(), config :: Chain.EVM.Config.t(), state :: term()) ::
              term()

  @doc """
  Callback will be called to get exact EVM version
  """
  @callback version() :: binary

  defmacro __using__(_opt) do
    quote do
      use GenServer, restart: :transient

      @behaviour Chain.EVM

      # Outside world URL for chain to be accessible
      @front_url Application.get_env(:chain, :front_url)

      require Logger

      alias Chain.SnapshotManager
      alias Chain.Snapshot.Details, as: SnapshotDetails

      # maximum amount of checks for evm started
      # system checks if evm started every 200ms
      @max_start_checks 30 * 5

      defmodule State do
        @moduledoc """
        Default structure for handling state into any EVM implementation

        Consist of this properties:
         - `status` - Chain status
         - `config` - default configuration for chain. Not available in implemented callback functions
         - `internal_state` - state for chain implementation

        `internal_state` - will be passed as state for all implemented callback functions
        """

        @type t :: %__MODULE__{
                status: Chain.EVM.status(),
                task: Chain.EVM.scheduled_task(),
                config: Chain.EVM.Config.t(),
                internal_state: term()
              }
        @enforce_keys [:config]
        defstruct status: :none, task: nil, config: nil, internal_state: nil
      end

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
        {:ok, %State{status: :starting, config: config}, {:continue, :start_chain}}
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

            # Adding chain process to `Chain.Watcher`
            %Config{http_port: http_port, ws_port: ws_port, db_path: db_path} = config
            Chain.Watcher.watch(http_port, ws_port, db_path)

            # Added. finishing
            {:noreply, %State{state | internal_state: internal_state}}

          {:error, err} ->
            Logger.error("#{config.id}: on start: #{err}")
            notify_status(config, :failed)
            {:stop, {:shutdown, :failed_to_start}, %State{state | status: :failed}}
        end
      end

      @doc false
      # method will be called after snapshot for evm was taken and EVM switched to `:snapshot_taken` status.
      # here evm will be started again
      def handle_continue(
            :start_after_snapshot,
            %State{status: status, config: config} = state
          )
          when status in ~w(snapshot_taken snapshot_reverted)a do
        Logger.debug("#{config.id} Starting chain after #{status}")
        # Start chain process
        {:ok, new_state} = start(config)
        # Schedule started check
        # Operation is async and `status: :active` will be set later
        # See: `handle_info({:check_started, _})`
        check_started(self())
        {:noreply, %State{state | internal_state: new_state}}
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
            {:check_started, retries},
            %State{internal_state: internal_state, config: config} = state
          ) do
        Logger.debug("#{config.id}: Check if evm JSON RPC became operational")

        case started?(config, internal_state) do
          true ->
            Logger.debug("#{config.id}: EVM Finally operational !")

            res =
              config
              |> handle_started(internal_state)
              # Marking chain as started and operational
              |> handle_action(%State{state | status: :active})

            # Send notification about chain active again
            notify_status(config, :active)

            # Returning result of action
            res

          false ->
            Logger.debug("#{config.id}: (#{retries}) not operational fully yet...")

            if retries >= @max_start_checks do
              notify_status(config, :failed)
              raise "#{config.id}: Failed to start evm (alive checks failed)"
            end

            check_started(self(), retries + 1)
            {:noreply, state}
        end
      end

      @doc false
      def handle_info(
            {_, :result, %Porcelain.Result{status: signal}},
            %State{status: :snapshot_taking, task: :take_snapshot, config: config} = state
          ) do
        %Config{id: id, db_path: db_path, type: type} = config
        Logger.debug("#{id}: Chain terminated for taking snapshot with exit status: #{signal}")

        try do
          details = SnapshotManager.make_snapshot!(db_path, type)
          Logger.debug("#{id}: Snapshot made, details: #{inspect(details)}")

          if pid = Map.get(config, :notify_pid) do
            send(pid, %Notification{id: id, event: :snapshot_taken, data: details})
          end

          notify_status(config, :snapshot_taken)

          {:noreply, %State{state | status: :snapshot_taken, task: nil},
           {:continue, :start_after_snapshot}}
        rescue
          err ->
            Logger.error("#{id} failed to make snapshot with error #{inspect(err)}")
            notify_status(config, :failed)
            {:noreply, %State{state | status: :failed}}
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

          if pid = Map.get(config, :notify_pid) do
            send(pid, %Notification{id: id, event: :snapshot_reverted, data: snapshot})
          end

          notify_status(config, :snapshot_reverted)

          {:noreply, %State{state | status: :snapshot_reverted, task: nil},
           {:continue, :start_after_snapshot}}
        rescue
          err ->
            Logger.error(
              "#{id} failed to revert snapshot #{inspect(snapshot)} with error #{inspect(err)}"
            )

            notify_status(config, :failed)
            {:noreply, %State{state | status: :failed}}
        end
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

        if pid = Map.get(config, :notify_pid) do
          Logger.debug("#{config.id} Sending notification to #{inspect(pid)}")

          send(pid, %Notification{
            id: config.id,
            event: :error,
            data: %{
              status: signal,
              message: "#{config.id} chain terminated with status #{status}"
            }
          })
        end

        case status do
          :active ->
            {:stop, :chain_failure, state}

          :starting ->
            {:stop, {:shutdown, :failed_to_start}, state}

          _ ->
            {:stop, :unknown_chain_status, state}
        end
      end

      def handle_info(msg, state) do
        Logger.debug("#{state.config.id}: Got msg #{inspect(msg)}")
        {:noreply, state}
      end

      @doc false
      def handle_call(
            :take_internal_snapshot,
            _from,
            %State{config: config, internal_state: internal_state} = state
          ) do
        config
        |> take_internal_snapshot(internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_call(
            {:revert_internal_snapshot, snapshot_id},
            _from,
            %State{config: config, internal_state: internal_state} = state
          ) do
        snapshot_id
        |> revert_internal_snapshot(config, internal_state)
        |> handle_action(state)
      end

      def handle_cast(
            :take_snapshot,
            %State{status: :active, config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id} stopping emv before taking snapshot")
        {:ok, new_state} = stop(config, internal_state)
        # Send notification about status change
        notify_status(config, :snapshot_taking)

        {:noreply,
         %State{state | status: :snapshot_taking, task: :take_snapshot, internal_state: new_state}}
      end

      @doc false
      def handle_cast(:take_snapshot, state) do
        Logger.error("No way we could take snapshot for non operational evm")
        {:noreply, state}
      end

      @doc false
      def handle_cast(
            {:revert_snapshot, snapshot},
            %State{status: :active, config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id} stopping emv before reverting snapshot")
        {:ok, new_state} = stop(config, internal_state)
        # Send notification about status change
        notify_status(config, :snapshot_reverting)

        {:noreply,
         %State{
           state
           | status: :snapshot_reverting,
             task: {:revert_snapshot, snapshot},
             internal_state: new_state
         }}
      end

      @doc false
      def handle_cast({:revert_snapshot, _}, state) do
        Logger.error("No way we could revert snapshot for non operational evm")
        {:noreply, state}
      end

      @doc false
      def handle_cast(
            :stop,
            %State{config: config, internal_state: internal_state} = state
          ) do
        case stop(config, internal_state) do
          {:ok, new_internal_state} ->
            Logger.debug("#{config.id}: Successfully stopped EVM")
            {:stop, :normal, %State{state | internal_state: new_internal_state}}

          {:error, err} ->
            Logger.error("#{config.id}: Failed to stop EVM with error: #{inspect(err)}")
            {:stop, :shutdown, state}
        end
      end

      @doc false
      def handle_cast(
            :start_mine,
            %State{config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id}: Starting mining process")

        config
        |> start_mine(internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_cast(
            :stop_mine,
            %State{config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id}: Stopping mining process")

        config
        |> stop_mine(internal_state)
        |> handle_action(state)
      end

      @doc false
      def terminate(
            reason,
            %State{config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id} Terminating evm with reason: #{inspect(reason)}")

        # I have to make terminate function with 3 params. ptherwise it might override 
        # `GenServer.terminate/2` 
        res = terminate(config.id, config, internal_state)

        # Check and clean path for all chains
        if Map.get(config, :clean_on_stop) do
          db_path = Map.get(config, :db_path)

          case File.rm_rf(db_path) do
            {:error, err} ->
              Logger.error(
                "#{config.id}: Failed to clean up #{db_path} with error: #{inspect(err)}"
              )

            _ ->
              Logger.debug("#{config.id}: Cleaned path after termination #{db_path}")
          end
        end

        # If exit reason is normal we could send notification that evm stopped
        if pid = Map.get(config, :notify_pid) do
          case reason do
            :normal ->
              send(pid, %Notification{id: config.id, event: :stopped})

            other ->
              send(pid, %Notification{
                id: config.id,
                event: :error,
                data: %{message: "#{inspect(other)}"}
              })
          end
        end

        # Returning termination result
        res
      end

      ######
      #
      # Default implementation functions for any EVM
      #
      ######

      @impl Chain.EVM
      def handle_msg(_str, _config, _state), do: :ignore

      @impl Chain.EVM
      def started?(%Config{id: id, http_port: http_port}, _) do
        Logger.debug("#{id}: Checking if EVM online")

        case JsonRpc.eth_coinbase("http://#{@front_url}:#{http_port}") do
          {:ok, <<"0x", _::binary>>} ->
            true

          _ ->
            false
        end
      end

      @impl Chain.EVM
      def handle_started(%{notify_pid: nil}, _internal_state), do: :ok

      def handle_started(
            %{id: id, notify_pid: pid, http_port: http_port, ws_port: ws_port},
            _internal_state
          ) do
        # Making request using async to not block scheduler
        [{:ok, coinbase}, {:ok, accounts}] =
          [
            # NOTE: here we will use localhost to avoid calling to chain from outside
            Task.async(fn -> JsonRpc.eth_coinbase("http://localhost:#{http_port}") end),
            Task.async(fn -> JsonRpc.eth_accounts("http://localhost:#{http_port}") end)
          ]
          |> Enum.map(&Task.await/1)

        details = %{
          coinbase: coinbase,
          accounts: accounts,
          rpc_url: "http://#{@front_url}:#{http_port}",
          ws_url: "ws://#{@front_url}:#{ws_port}"
        }

        send(pid, %Notification{id: id, event: :started, data: details})
        :ok
      end

      @impl Chain.EVM
      def version(), do: "x.x.x"

      @impl Chain.EVM
      def start_mine(_, _), do: :ignore

      @impl Chain.EVM
      def stop_mine(_, _), do: :ignore

      @impl Chain.EVM
      def take_internal_snapshot(_config, state), do: {:reply, {:error, :not_implemented}, state}

      @impl Chain.EVM
      def revert_internal_snapshot(_id, _config, _state), do: :ignore

      ########
      #
      # Private functions for EVM
      #
      ########

      # notify listener about evm status change
      defp notify_status(%Config{id: id, notify_pid: nil}, _), do: :ok

      defp notify_status(%Config{id: id, notify_pid: pid}, status) do
        send(pid, %Notification{
          id: id,
          event: :status_changed,
          data: status
        })
      end

      # Internal handler for evm actions
      defp handle_action(reply, state) do
        case reply do
          :ok ->
            {:noreply, state}

          :ignore ->
            {:noreply, state}

          {:ok, new_internal_state} ->
            {:noreply, %State{state | internal_state: new_internal_state}}

          {:reply, reply, new_internal_state} ->
            {:reply, reply, %State{state | internal_state: new_internal_state}}

          {:error, err} ->
            Logger.error("#{state.config.id}: action failed with error: #{inspect(err)}")
        end
      end

      # Send msg to check if evm started
      # Checks when EVM is started in async mode.
      defp check_started(pid, retries \\ 0) do
        Process.send_after(pid, {:check_started, retries}, 200)
      end

      # Allow to override functions
      defoverridable handle_started: 2,
                     started?: 2,
                     handle_msg: 3,
                     start_mine: 2,
                     stop_mine: 2,
                     version: 0,
                     take_internal_snapshot: 2,
                     revert_internal_snapshot: 3
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
