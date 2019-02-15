defmodule Chain.EVM.Notification do
  @moduledoc """
  Default EVM chain notification structure.

  For example on chain start it should fire event `:started` and so on.
  Example:

  ```elixir
  %Chain.EVM.Notification{
    id: "15054686724791906538",
    event: :started, 
    data: %{
      accounts: ["0x51ef0fe1fe60af27f400ab42ddc9a6b99b277d38"],
      coinbase: "0x51ef0fe1fe60af27f400ab42ddc9a6b99b277d38",
      rpc_url: "http://localhost:8545",
      ws_url: "ws://localhost:8546"
    }
  }
  ```
  """

  @typedoc """
  Event type that should be sent by chain implementation
  """
  @type event ::
          :started | :stopped | :error | :snapshot_taken | :snapshot_reverted | :status_changed

  @type t :: %__MODULE__{
          id: Chain.evm_id(),
          event: Chain.EVM.Notification.event(),
          data: map()
        }

  @enforce_keys [:id, :event]
  defstruct id: nil, event: nil, data: %{}

  @doc """
  Just creating new `Chain.EVM.Notification` structure
  """
  @spec new(Chain.evm_id(), atom(), term()) :: :ok
  def new(id, event, data \\ %{}), do: %__MODULE__{id: id, event: event, data: data}

  @doc """
  Send notification to given pid.

  You could pass receiver in several formats: 
   - `pid` - Normal pid that should be notified.
   - `%{notify_pid: pid}` - Config with `notify_pid` key.
  """
  @spec send(%{notify_pid: pid()} | pid | module, Chain.evm_id(), atom(), term()) :: :ok
  def send(receiver, id, event, data \\ %{})

  def send(nil, _, _, _), do: :ok

  def send(%{notify_pid: pid}, id, event, data),
    do: send(pid, id, event, data)

  def send(pid, id, event, data),
    do: send(pid, __MODULE__.new(id, event, data))
end

defimpl Jason.Encoder, for: Chain.EVM.Notification do
  def encode(value, opts) do
    value
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end
