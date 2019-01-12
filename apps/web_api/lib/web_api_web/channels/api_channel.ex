defmodule WebApiWeb.ApiChannel do
  @moduledoc """
  Default channel for API manipulation
  """

  use Phoenix.Channel, log_join: false, log_handle_in: :debug

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
  Get list of snapshots for given chain type
  """
  def handle_in("listSnapshots", %{"chain" => chain}, socket) do
    {:reply, {:ok, %{snapshots: Chain.SnapshotManager.by_chain(chain)}}, socket}
  end
end
