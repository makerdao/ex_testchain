defmodule Chain.EVM do
  @moduledoc """
  EVM abscraction. Each EVMs have to implement this abstraction.
  """

  require Logger

  alias Chain.EVM.Config

  @typedoc """
  Default evm action reply message
  """
  @type action_reply :: :ok | {:ok, state :: any()} | {:error, term()}

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
  @callback started?(state :: any()) :: boolean()

  @doc """
  Callback will be invoked after EVM started and confirmed it by `started?/1`
  """
  @callback handle_started(state :: any()) :: action_reply()

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
  """
  @callback take_snapshot(path_to :: binary, state :: any()) :: action_reply()

  @doc """
  This callback is called just before the Process goes down. This is a good place for closing connections.
  """
  @callback terminate(state :: term()) :: term()

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
        GenServer.start_link(__MODULE__, config, name: {:via, Registry, {Chain.EVM.Registry, id}})
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

        case started?(internal_state) do
          true ->
            Logger.debug("#{id}: EVM Finally started !")
            internal_state
            |> handle_started()
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

      def handle_cast(
            {:take_snapshot, path_to},
            %State{id: id, internal_state: internal_state} = state
          ) do
        Logger.debug("#{id}: Taking chain snapshot to #{path_to}")

        path_to
        |> take_snapshot(internal_state)
        |> handle_action(state)
      end

      @doc false
      def terminate(reason, %State{id: id, internal_state: internal_state} = state) do
        Logger.debug("#{id} Terminating evm with reason: #{inspect(reason)}")
        terminate(internal_state)
      end

      @doc """
      Basic implementation for handle_started
      """
      def handle_started(_internal_state), do: :ok

      # Internal handler for evm actions
      defp handle_action(reply, %State{id: id} = state) do
        case reply do
          :ok ->
            {:noreply, state}

          {:ok, new_internal_state} ->
            {:noreply, %State{state | internal_state: new_internal_state}}

          {:error, err} ->
            Logger.error("#{id}: action failed with error: #{inspect(err)}")
        end
      end

      # Send msg to check if evm started
      defp check_started(pid, retries \\ 0) do
        Process.send_after(pid, {:check_started, retries}, 1_000)
      end

      # Allow to override `handle_started/1` function
      defoverridable handle_started: 1
    end
  end
end
