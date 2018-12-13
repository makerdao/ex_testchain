defmodule WebApiWeb.ApiChannel do
  use Phoenix.Channel

  alias Chain.EVM.Config
  alias WebApi.ChainHelper
  alias WebApi.ChainMessageHandler

  def join(_, _, socket), do: {:ok, %{message: "Welcome to ExTestchain !"}, socket}

  @doc """
  Start new chain handler
  """
  def handle_in("start", payload, socket) do
    config = %Config{
      type: (Map.get(payload, "type") == "geth" && :geth) || :ganache,
      id: Map.get(payload, "id"),
      http_port: Map.get(payload, "http_port", 8545),
      ws_port: Map.get(payload, "ws_port", 8546),
      db_path: Map.get(payload, "db_path", ""),
      accounts: Map.get(payload, "accounts", 1),
      block_mine_time: Map.get(payload, "block_mine_time", 0),
      clean_on_stop: Map.get(payload, "clean_on_stop", false),
      notify_pid: ChainMessageHandler
    }

    ChainMessageHandler.notify_on(:started, self(), socket_ref(socket))

    {:ok, id} = Chain.start(config)
    {:reply, {:ok, %{id: id}}, socket}
  end

  def handle_info({:started, data, ref}, socket) do
    reply(ref, {:started, Map.from_struct(data)})
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    IO.inspect(msg)
    {:noreply, socket}
  end
end
