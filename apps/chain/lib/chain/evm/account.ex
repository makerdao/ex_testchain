defmodule Chain.EVM.Account do
  @moduledoc """
  EVM account representation

  **Note**: address should start from 0x
  """

  # Default balance in wei
  @default_balance 100_000_000_000_000_000_000_000

  @type t :: %__MODULE__{
          address: binary,
          priv_key: binary,
          balance: non_neg_integer
        }

  defstruct address: "", priv_key: "", balance: @default_balance

  @spec new() :: Chain.EVM.Account.t()
  def new() do
    %{address: address, private_key: key} = Ethereum.Wallet.generate()
    %__MODULE__{address: address, priv_key: key}
  end

  @doc """
  Generate new private key for account
  """
  @spec private_key() :: binary
  def private_key() do
    {_pub, priv} = generate_pair()

    priv
    |> Base.encode16()
    |> String.downcase()
  end

  # Generate pair of keys
  # all ethereum addresses are based on valid ECDH secp256k1 keys
  defp generate_pair(), do: :crypto.generate_key(:ecdh, :secp256k1)
end

defimpl Jason.Encoder, for: Chain.EVM.Account do
  def encode(value, opts) do
    value
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end
