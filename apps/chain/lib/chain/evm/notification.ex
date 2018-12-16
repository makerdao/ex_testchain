defmodule Chain.EVM.Notification do
  @moduledoc """
  Default EVM chain notification structure.

  For example on chain start it should fire event `:started` and so on.
  Example:

  ```elixir
  %Chain.EVM.Notification{
    id: "15054686724791906538",
    event: :started, 
    data: %Chain.EVM.Process{
      accounts: ["0x51ef0fe1fe60af27f400ab42ddc9a6b99b277d38"],
      coinbase: "0x51ef0fe1fe60af27f400ab42ddc9a6b99b277d38",
      id: "15054686724791906538",
      rpc_url: "http://localhost:8545",
      ws_url: "ws://localhost:8546"
    }
  }
  ```
  """

  @typedoc """
  Event type that should be sent by chain implementation
  """
  @type event :: :started | :stopped | :error | :snapshot_taken | :snapshot_reverted

  @type t :: %__MODULE__{
          id: Chain.evm_id(),
          event: Chain.EVM.Notification.event(),
          data: map()
        }

  @enforce_keys [:id, :event]
  defstruct id: nil, event: nil, data: %{}
end
