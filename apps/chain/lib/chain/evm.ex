defmodule Chain.EVM do
  @moduledoc """
  EVM abscraction. Each EVMs have to implement this abstraction.
  """

  require Logger

  alias Chain.EVM.Config

  # Amount of ms the server is allowed to spend initializing or it will be terminated
  @timeout Application.get_env(:chain, :kill_timeout, 60_000)

  @typedoc """
  Default evm action reply message
  """
  @type action_reply ::
          :ok
          | {:ok, state :: any()}
          | {:reply, reply :: term(), state :: any()}
          | {:error, term()}

  @doc """
  This callback is called on starting evm instance. Here EVM should be started and validated RPC.
  The argument is configuration for EVM.
  In must return `{:ok, state}`, that `state` will be keept as in `GenServer` and can be 
  retrieved in futher functions.
  """
  @callback start(config :: Config.t()) :: {:ok, state :: any()} | {:error, term()}

  @doc """
  This callback will be called when system will need to stop EVM.
  """
  @callback stop(state :: any()) :: action_reply()

  @doc """
  Callback is called to check if EVM started and responsive
  """
  @callback started?(config :: Chain.EVM.Config.t(), state :: any()) :: boolean()

  @doc """
  Callback will be invoked after EVM started and confirmed it by `started?/2`
  """
  @callback handle_started(config :: Chain.EVM.Config.t(), state :: any()) :: action_reply()

  @doc """
  Handle incomming message from outside world
  """
  @callback handle_msg(msg :: term(), state :: any()) :: action_reply()

  @doc """
  Should start mining process for EVM
  """
  @callback start_mine(state :: any()) :: action_reply()

  @doc """
  Stop mining process for EVM
  """
  @callback stop_mine(state :: any()) :: action_reply()

  @doc """
  Callback will be invoked on take snapshot command. Chain have to perform snapshot operation
  and store chain data to given `path_to`.

  This function have to return `{:reply, result :: any(), state :: any()}` tuple. 
  Result will be returned to caller using `GenServer.handle_call/3` callback.

  Response example:
  In case of success function have to return: `{:reply, {:ok, path_od_id}, state}`
  In case of error: `{:reply, {:error, :not_implemented}, state`
  """
  @callback take_snapshot(path_to :: binary, state :: any()) :: action_reply()

  @doc """
  Callback will be invoked on revert snapshot command.
  Chain have to revert snapshot from given path (or id for `ganache`)

  This function have to return `{:reply, result :: any(), state :: any()}` tuple. 
  Result will be returned to caller using `GenServer.handle_call/3` callback.

  If `path_or_id` snapshot does not exist `{:reply, {:error, term()}, state}` should be returned
  In case of success - `{:reply, :ok, state}` should be returned
  """
  @callback revert_snapshot(path_or_id :: binary, state :: any()) :: action_reply()

  @doc """
  This callback is called just before the Process goes down. This is a good place for closing connections.
  """
  @callback terminate(state :: term()) :: term()

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
        @moduledoc false

        @type t :: %__MODULE__{
                id: non_neg_integer(),
                config: Chain.EVM.Config.t(),
                internal_state: term()
              }
        defstruct id: nil, config: nil, internal_state: nil
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
      def init(%Config{id: id} = config) do
        {:ok, %State{id: id, config: config}, {:continue, :start_chain}}
      end

      @doc false
      def handle_continue(:start_chain, %State{id: id, config: config} = state) do
        case start(config) do
          {:ok, internal_state} ->
            Logger.debug("#{id}: Started successfully !")
            # Schedule started check
            check_started(self())
            {:noreply, %State{state | internal_state: internal_state}}

          {:error, err} ->
            Logger.error("#{id}: on start: #{err}")
            {:stop, {:shutdown, :failed_to_start}, state}
        end
      end

      @doc false
      def handle_info(
            {_pid, :data, :out, msg},
            %State{internal_state: internal_state} = state
          ) do
        msg
        |> String.replace_prefix("/n", "")
        |> String.replace_prefix(" ", "")
        |> handle_msg(internal_state)
        |> handle_action(state)
      end

      def handle_info(
            {:check_started, retries},
            %State{id: id, internal_state: internal_state, config: config} = state
          ) do
        Logger.debug("#{id}: Check if evm started")

        case started?(config, internal_state) do
          true ->
            Logger.debug("#{id}: EVM Finally started !")

            config
            |> handle_started(internal_state)
            |> handle_action(state)

          false ->
            Logger.debug("#{id}: (#{retries}) not started fully yet...")

            if retries >= @max_start_checks do
              raise "#{id}: Failed to start evm"
            end

            check_started(self(), retries + 1)
            {:noreply, state}
        end
      end

      def handle_info(msg, %State{id: id} = state) do
        Logger.debug("#{id}: Got msg #{inspect(msg)}")
        {:noreply, state}
      end

      @doc false
      def handle_call(
            {:take_snapshot, path_to},
            _from,
            %State{id: id, internal_state: internal_state} = state
          ) do
        Logger.debug("#{id}: Taking chain snapshot to #{path_to}")

        path_to
        |> take_snapshot(internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_call(
            {:revert_snapshot, path_or_id},
            _from,
            %State{id: id, internal_state: internal_state} = state
          ) do
        Logger.debug("#{id}: Reverting chain snapshot from #{path_or_id}")

        path_or_id
        |> revert_snapshot(internal_state)
        |> handle_action(state)
      end

      @doc false
      def handle_cast(:stop, %State{id: id, internal_state: internal_state} = state) do
        case stop(internal_state) do
          {:ok, new_internal_state} ->
            Logger.debug("#{id}: Successfully stopped EVM")
            {:stop, :normal, %State{state | internal_state: new_internal_state}}

          {:error, err} ->
            Logger.error("#{id}: Failed to stop EVM with error: #{inspect(err)}")
            {:stop, :shutdown, state}
        end
      end

      @doc false
      def handle_cast(:start_mine, %State{id: id, internal_state: internal_state} = state) do
        Logger.debug("#{id}: Starting mining process")

        internal_state
        |> start_mine()
        |> handle_action(state)
      end

      @doc false
      def handle_cast(:stop_mine, %State{id: id, internal_state: internal_state} = state) do
        Logger.debug("#{id}: Stopping mining process")

        internal_state
        |> stop_mine()
        |> handle_action(state)
      end

      @doc false
      def terminate(reason, %State{id: id, internal_state: internal_state} = state) do
        Logger.debug("#{id} Terminating evm with reason: #{inspect(reason)}")
        terminate(internal_state)
      end

      @impl Chain.EVM
      def handle_msg(str, %{id: id} = state) do
        {:ok, state}
      end

      @impl Chain.EVM
      def started?(%{id: id, http_port: http_port}, _) do
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

        send(pid, process)
        :ok
      end

      @impl Chain.EVM
      def version(), do: "x.x.x"

      @impl Chain.EVM
      def take_snapshot(path_to, %State{id: id} = state) do
        Logger.warn("#{id} take_snapshot not implemented")
        {:reply, {:error, :not_implemented}, state}
      end

      @impl Chain.EVM
      def revert_snapshot(path_or_id, %State{id: id} = state) do
        Logger.warn("#{id} revert_snapshot not implemented")
        {:reply, :ok, state}
      end

      # Internal handler for evm actions
      defp handle_action(reply, %State{id: id} = state) do
        case reply do
          :ok ->
            {:noreply, state}

          {:ok, new_internal_state} ->
            {:noreply, %State{state | internal_state: new_internal_state}}

          {:reply, reply, new_internal_state} ->
            {:reply, reply, %State{state | internal_state: new_internal_state}}

          {:error, err} ->
            Logger.error("#{id}: action failed with error: #{inspect(err)}")
        end
      end

      # Send msg to check if evm started
      defp check_started(pid, retries \\ 0) do
        Process.send_after(pid, {:check_started, retries}, 1_000)
      end

      # Allow to override functions
      defoverridable handle_started: 2,
                     started?: 2,
                     handle_msg: 2,
                     version: 0,
                     take_snapshot: 2,
                     revert_snapshot: 2
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
