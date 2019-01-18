defmodule Storage.SnapshotStore do
  @moduledoc """
  Module that handle snapshots storage
  """
  use GenServer
  require Logger

  alias Chain.Snapshot.Details, as: SnapshotDetails

  # DB file name
  @table "snapshots"

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  def init(:ok) do
    unless File.dir?(db_path()) do
      File.mkdir(db_path())
    end

    :dets.open_file(table(), type: :set)
  end

  @doc false
  def terminate(_, _) do
    Logger.debug("#{__MODULE__} terminating... Closing DETS...")
    :dets.close(table())
  end

  @doc """
  Store new snapshot into local DB
  """
  @spec store(Chain.Snapshot.Details.t()) :: :ok | {:error, term()}
  def store(%SnapshotDetails{id: id, chain: chain} = snapshot),
    do: :dets.insert(table(), {id, chain, snapshot})

  @doc """
  Load snapshot details by id
  In case of error it might raise an exception
  """
  @spec by_id(binary) :: Chain.Snapshot.Details.t() | nil
  def by_id(id) do
    case :dets.lookup(table(), id) do
      [] ->
        nil

      [{^id, _, snapshot}] ->
        snapshot
    end
  end

  @doc """
  Load list of existing snapshots by chain type
  """
  @spec by_chain(Chain.evm_type()) :: [Chain.Snapshot.Details.t()]
  def by_chain(chain) do
    table()
    |> :dets.match({:_, chain, :"$1"})
    |> Enum.map(fn [snap] -> snap end)
  end

  @doc """
  Remove snapshot details from local DB
  """
  @spec remove(binary) :: :ok
  def remove(id), do: :dets.delete(table(), id)

  # Get DB path
  defp db_path() do
    :storage
    |> Application.get_env(:dets_db_path)
    |> Path.expand()
  end

  # Get full table path
  defp table() do
    db_path()
    |> Path.join(@table)
    |> String.to_atom()
  end
end
