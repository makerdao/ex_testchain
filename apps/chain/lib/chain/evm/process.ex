defmodule Chain.EVM.Process do
  @moduledoc """
  EVM Process identifier
  """
  @type t :: %__MODULE__{
          id: Chain.evm_id(),
          coinbase: binary,
          accounts: [Chain.EVM.Account.t()],
          rpc_url: binary,
          ws_url: binary,
          gas_limit: pos_integer()
        }

  @enforce_keys [:id]
  defstruct id: nil, coinbase: "", accounts: [], rpc_url: "", ws_url: "", gas_limit: 6_000_000
end

defimpl Jason.Encoder, for: Chain.EVM.Process do
  def encode(value, opts) do
    value
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end
