defmodule Storage.Provider.Dets do
  @moduledoc """
  DETS storage implementation
  """
  use GenServer
  require Logger

  @behaviour Storage.Provider

  @table "chains"

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc false
  @impl GenServer
  def init(_) do
    unless File.dir?(db_path()) do
      File.mkdir(db_path())
    end

    :dets.open_file(table(), type: :set)
  end

  @doc false
  @impl GenServer
  def terminate(_, _),
    do: :dets.close(table())

  @impl Storage.Provider
  def store(%{id: id, status: status} = record),
    do: :dets.insert(table(), {id, status, record})

  @impl Storage.Provider
  def remove(id),
    do: :dets.delete(table(), id)

  @impl Storage.Provider
  def list() do
    table()
    |> :dets.match({:_, :_, :"$1"})
    |> Enum.map(fn [chain] -> chain end)
  end

  @impl Storage.Provider
  def get(id) do
    case :dets.lookup(table(), id) do
      [] ->
        nil

      [{_, _, chain}] ->
        chain

      {:error, err} ->
        {:error, err}
    end
  end

  @impl Storage.Provider
  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :transient
    }
  end

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
