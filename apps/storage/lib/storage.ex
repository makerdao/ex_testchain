defmodule Storage do
  @moduledoc """
  Storage system for chains
  """

  @doc """
  Storing/updating chain in DB
  """
  @spec store(%{id: binary}, binary, map()) :: :ok | {:error, term()}
  def store(config, status, other \\ %{})

  def store(%{__struct__: _} = config, status, other) do
    config
    |> Map.from_struct()
    |> store(status, other)
  end

  def store(%{id: _} = config, status, other) do
    record =
      other
      |> Map.merge(config)
      |> Map.merge(%{status: status})

    apply(module(), :store, [record])
  end

  @doc """
  Remove chain by id from DB
  """
  @spec remove(Chain.evm_id()) :: :ok | {:error, term()}
  def remove(id), do: apply(module(), :remove, [id])

  @doc """
  Load list of stored chains
  """
  @spec list() :: [map()]
  def list(), do: apply(module(), :list, [])

  @doc """
  Get chain details by chain id
  """
  @spec get(binary) :: nil | %{id: binary, status: atom()} | {:error, term()}
  def get(id), do: apply(module(), :get, [id])

  # Ger provider for stage system
  defp module(), do: Application.get_env(:storage, :provider)
end
