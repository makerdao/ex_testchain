defmodule WebApiWeb.ApiChannel do
  use Phoenix.Channel

  alias Chain.EVM.Config
  alias WebApi.ChainHelper

  def join(_, _, socket), do: {:ok, %{message: "Welcome to ExTestchain !"}, socket}

  def handle_in("start", payload, socket) do
    {:ok, pid} = ChainHelper.spawn_notification_handler(self(), socket_ref(socket))

    config = %Config{
      type: (Map.get(payload, "type") == "geth" && :geth) || :ganache,
      id: Map.get(payload, "id"),
      http_port: Map.get(payload, "http_port", 8545),
      ws_port: Map.get(payload, "ws_port", 8546),
      db_path: Map.get(payload, "db_path", ""),
      accounts: Map.get(payload, "accounts", 1),
      notify_pid: pid
    }

    {:ok, id} = Chain.start(config)
    {:noreply, socket}
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
