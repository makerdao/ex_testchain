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
            {:noreply, %State{state | internal_state: internal_state}}

          {:error, err} ->
            Logger.error("#{id}: on start: #{err}")
            {:stop, {:shutdown, :failed_to_start}, state}
        end
      end

      @doc false
      def handle_info(msg, %State{id: id, internal_state: internal_state} = state) do
        Logger.debug("#{id}: Handling message from port")

        msg
        |> handle_msg(internal_state)
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
    end
  end
end
