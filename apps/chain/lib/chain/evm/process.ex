defmodule Chain.EVM.Process do
  @moduledoc """
  EVM Process identifier
  """
  @type t :: %__MODULE__{
          id: non_neg_integer(),
          coinbase: binary,
          accounts: [binary | {binary, non_neg_integer()}],
          rpc_url: binary,
          ws_url: binary
        }

  @enforce_keys [:id]
  defstruct id: nil, coinbase: "", accounts: [], rpc_url: "", ws_url: ""
end
