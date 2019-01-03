defmodule Chain.Snapshot.Details do
  @moduledoc """
  Snapshot details
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
