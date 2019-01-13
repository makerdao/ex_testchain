defmodule Storage.Provider.Dets do
  @moduledoc """
  DETS storage implementation
  """
  use GenServer
  require Logger

  @behaviour Storage.Provider

  @table :chains

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, @table, name: __MODULE__)
  end

  @doc false
  @impl GenServer
  def init(table) do
    :dets.open_file(table, type: :set)
  end

  @doc false
  @impl GenServer
  def terminate(_, table) do
    :dets.close(table)
  end

  @impl Storage.Provider
  def store(%{id: id, status: status} = record), do: :dets.insert(@table, {id, status, record})

  @impl Storage.Provider
  def remove(id), do: :dets.delete(@table, id)

  @impl Storage.Provider
  def list() do
    @table
    |> :dets.match({:_, :_, :"$1"})
    |> Enum.map(fn [chain] -> chain end)
  end

  @impl Storage.Provider
  def get(id) do
    case :dets.lookup(@table, id) do
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
end
