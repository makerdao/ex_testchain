defmodule WebApiWeb.ApiChannel do
  @moduledoc """
  Default channel for API manipulation
  """

  use Phoenix.Channel, log_join: false, log_handle_in: :debug

  require Logger

  alias Chain.EVM.Config
  alias WebApi.ChainMessageHandler

  def join(_, _, socket), do: {:ok, %{message: "Welcome to ExTestchain !"}, socket}

  @doc """
  Start new chain handler
  """
  def handle_in("start", payload, socket) do
    config = %Config{
      type: String.to_atom(Map.get(payload, "type", "ganache")),
      # id: Map.get(payload, "id"),
      # http_port: Map.get(payload, "http_port"),
      # ws_port: Map.get(payload, "ws_port"),
      db_path: Map.get(payload, "db_path", ""),
      accounts: Map.get(payload, "accounts", 1),
      block_mine_time: Map.get(payload, "block_mine_time", 0),
      clean_on_stop: Map.get(payload, "clean_on_stop", false),
      description: Map.get(payload, "description", ""),
      notify_pid: ChainMessageHandler
    }

    case Chain.start(config) do
      {:ok, id} ->
        # Subscribing to notification :started and sending response to socket
        # ChainMessageHandler.notify_on(id, :started, self(), socket_ref(socket))
        {:reply, {:ok, %{id: id}}, socket}

      {:error, err} ->
        {:reply, {:error, %{message: err}}, socket}
    end
  end

  @doc """
  Start existing chain
  """
  def handle_in("start_existing", %{"id" => id}, socket) do
    case Chain.start_existing(id, ChainMessageHandler) do
      {:ok, id} ->
        # Subscribing to notification :started and sending response to socket
        # ChainMessageHandler.notify_on(id, :started, self(), socket_ref(socket))
        {:reply, {:ok, %{id: id}}, socket}

      {:error, err} ->
        {:reply, {:error, %{message: err}}, socket}
    end
  end

  @doc """
  Get list of snapshots for given chain type
  """
  def handle_in("list_snapshots", %{"chain" => chain}, socket) do
    {:reply, {:ok, %{snapshots: Chain.SnapshotManager.by_chain(chain)}}, socket}
  end

  def handle_in("list_chains", _, socket) do
    case Storage.list() do
      list when is_list(list) ->
        {:reply, {:ok, %{chains: list}}, socket}

      {:error, err} ->
        Logger.error("Error retreiving list of chains #{inspect(err)}")
        {:reply, {:error, %{message: "Failed to load list of chains"}}, socket}
    end
  end

  def handle_in("remove_chain", %{"id" => id}, socket) do
    with false <- Chain.alive?(id),
         :ok <- Chain.clean(id) do
      {:reply, {:ok, %{message: "Chain removed"}}, socket}
    else
      true ->
        {:reply, {:error, %{message: "Chain is running. Could not be removed"}}, socket}

      _ ->
        {:reply, {:error, %{message: "Something wrong on removing chain"}}, socket}
    end
  end
end
