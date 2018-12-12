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
  Default evm action reply message
  """
  @type action_reply ::
          :ok
          | :ignore
          | {:ok, state :: any()}
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
  Callback will be invoked on take snapshot command. Chain have to perform snapshot operation
  and store chain data to given `path_to`.

  This function have to return `{:reply, result :: any(), state :: any()}` tuple. 
  Result will be returned to caller using `GenServer.handle_call/3` callback.

  Response example:
  In case of success function have to return: `{:reply, {:ok, path_od_id}, state}`
  In case of error: `{:reply, {:error, :not_implemented}, state`

  If system tries to make a snapshot to directory. Make sure it's empty !
  """
  @callback take_snapshot(path_to :: binary, config :: Chain.EVM.Config.t(), state :: any()) ::
              action_reply()

  @doc """
  Callback will be invoked on revert snapshot command.
  Chain have to revert snapshot from given path (or id for `ganache`)

  This function have to return `{:reply, result :: any(), state :: any()}` tuple. 
  Result will be returned to caller using `GenServer.handle_call/3` callback.

  If `path_or_id` snapshot does not exist `{:reply, {:error, term()}, state}` should be returned
  In case of success - `{:reply, :ok, state}` should be returned
  """
  @callback revert_snapshot(path_or_id :: binary, config :: Chain.EVM.Config.t(), state :: any()) ::
              action_reply()

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

      require Logger

      # maximum amount of checks for evm started
      # system checks if evm started every second
      @max_start_checks 10

      defmodule State do
        @moduledoc """
        Default structure for handling state into any EVM implementation

        Consist of this properties:
         - `started` - boolean flag, shows if chain started successfully. it will be set only once
         - `config` - default configuration for chain. Not available in implemented callback functions
         - `internal_state` - state for chain implementation

        `internal_state` - will be passed as state for all implemented callback functions
        """

        @type t :: %__MODULE__{
                started: boolean,
                config: Chain.EVM.Config.t(),
                internal_state: term()
              }
        @enforce_keys [:config]
        defstruct started: false, config: nil, internal_state: nil
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
        {:ok, %State{config: config}, {:continue, :start_chain}}
      end

      @doc false
      def handle_continue(:start_chain, %State{config: config} = state) do
        case start(config) do
          {:ok, internal_state} ->
            Logger.debug("#{config.id}: Chain init started successfully ! Waiting for JSON-RPC.")

            # Schedule started check
            check_started(self())

            # Adding chain process to `Chain.Watcher`
            %Config{http_port: http_port, ws_port: ws_port, db_path: db_path} = config
            Chain.Watcher.watch(http_port, ws_port, db_path)

            # Added. finishing
            {:noreply, %State{state | internal_state: internal_state}}

          {:error, err} ->
            Logger.error("#{config.id}: on start: #{err}")
            {:stop, {:shutdown, :failed_to_start}, state}
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
            {:check_started, retries},
            %State{internal_state: internal_state, config: config} = state
          ) do
        Logger.debug("#{config.id}: Check if evm started")

        case started?(config, internal_state) do
          true ->
            Logger.debug("#{config.id}: EVM Finally started !")

            config
            |> handle_started(internal_state)
            # Marking chain as started
            |> handle_action(%State{state | started: true})

          false ->
            Logger.debug("#{config.id}: (#{retries}) not started fully yet...")

            if retries >= @max_start_checks do
              raise "#{config.id}: Failed to start evm"
            end

            check_started(self(), retries + 1)
            {:noreply, state}
        end
      end

      # Idea about this is:
      # When Porcelain will spawn an OS process it will handle it's termination.
      # And on termination we will get message `{<from>, :result, %Porcelain.Result{} | nil}`
      # So we have to check if our chain is already started (`%State{started: boolean}`)
      # And if it was started we have to restart chain (internal failure)
      # But if chain was not yet started - we have to ignore this and just terminate PID
      @doc false
      def handle_info(
            {_, :result, %Porcelain.Result{status: nil}},
            %State{config: %{id: id}} = state
          ) do
        Logger.debug("#{id}: Chain terminated manually without any error !")
        {:noreply, state}
      end

      def handle_info(
            {_, :result, %Porcelain.Result{status: status}},
            %State{started: started, config: config} = state
          ) do
        Logger.error(
          "#{config.id} Chain failed with status: #{inspect(status)}. Check logs: #{
            Map.get(config, :output, "")
          }"
        )

        if pid = Map.get(config, :notify_pid) do
          Logger.debug("#{config.id} Sending notification to #{inspect(pid)}")

          send(pid, %Notification{
            id: config.id,
            event: :error,
            data: %{
              status: status,
              message: "#{config.id} chain terminated with status #{status}"
            }
          })
        end

        case started do
          true ->
            {:stop, :chain_failure, state}

          false ->
            {:stop, {:shutdown, :failed_to_start}, state}
        end
      end

      def handle_info(msg, state) do
        Logger.debug("#{state.config.id}: Got msg #{inspect(msg)}")
        {:noreply, state}
      end

      # this is workaround for empty snapshot path.
      # In case of empty path - it will be generated by /base/snapshot/folder/#{id}
      @doc false
      def handle_call({:take_snapshot, ""}, from, %State{config: %{id: id}} = state) do
        path =
          Application.get_env(:chain, :snapshot_base_path)
          |> Path.expand()
          |> Path.join(id)

        # Calling correct function
        handle_call({:take_snapshot, path}, from, state)
      end

      def handle_call(
            {:take_snapshot, path_to},
            _from,
            %State{config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id}: Taking chain snapshot to #{path_to}")

        path_to
        |> take_snapshot(config, internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_call(
            {:revert_snapshot, path_or_id},
            _from,
            %State{config: config, internal_state: internal_state} = state
          ) do
        Logger.debug("#{config.id}: Reverting chain snapshot from #{path_or_id}")

        path_or_id
        |> revert_snapshot(config, internal_state)
        |> handle_action(state)
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

        # If exit reason is normal we could send notification that evm stopped
        if (pid = Map.get(config, :notify_pid)) && reason == :normal do
          send(pid, %Notification{id: config.id, event: :stopped})
        end

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

        case JsonRpc.eth_coinbase("http://localhost:#{http_port}") do
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
            Task.async(fn -> JsonRpc.eth_coinbase("http://localhost:#{http_port}") end),
            Task.async(fn -> JsonRpc.eth_accounts("http://localhost:#{http_port}") end)
          ]
          |> Enum.map(&Task.await/1)

        process = %Chain.EVM.Process{
          id: id,
          coinbase: coinbase,
          accounts: accounts,
          rpc_url: "http://localhost:#{http_port}",
          ws_url: "ws://localhost:#{ws_port}"
        }

        send(pid, %Notification{id: id, event: :started, data: process})
        :ok
      end

      @impl Chain.EVM
      def version(), do: "x.x.x"

      @impl Chain.EVM
      def start_mine(_, _), do: :ignore

      @impl Chain.EVM
      def stop_mine(_, _), do: :ignore

      @impl Chain.EVM
      def take_snapshot(path_to, _config, state),
        do: {:reply, {:error, :not_implemented}, state}

      @impl Chain.EVM
      def revert_snapshot(path_or_id, _config, _state), do: :ignore

      @impl Chain.EVM
      def take_internal_snapshot(_config, state), do: {:reply, {:error, :not_implemented}, state}

      @impl Chain.EVM
      def revert_internal_snapshot(_id, _config, _state), do: :ignore

      ########
      #
      # Private functions for EVM
      #
      ########

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
      defp check_started(pid, retries \\ 0) do
        Process.send_after(pid, {:check_started, retries}, 1_000)
      end

      # Allow to override functions
      defoverridable handle_started: 2,
                     started?: 2,
                     handle_msg: 3,
                     start_mine: 2,
                     stop_mine: 2,
                     version: 0,
                     take_snapshot: 3,
                     revert_snapshot: 3,
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
