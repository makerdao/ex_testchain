defmodule Chain.Snapshot.Details do
  @moduledoc """
  Snapshot details

   - `id` - Snapshot ID
   - `chain` - Chain type (ganache|geth|geth_vdb)
   - `description` - Snapshot description
   - `date` - Creation date
   - `path` - Path to snapshot file
  """

  @type t :: %__MODULE__{
          id: binary,
          chain: Chain.evm_type(),
          description: binary,
          date: DateTime.t(),
          path: binary
        }

  defstruct id: "", chain: nil, description: "", date: DateTime.utc_now(), path: ""
end

defimpl Jason.Encoder, for: Chain.Snapshot.Details do
  def encode(value, opts) do
    value
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end
