defmodule WebApi.ChainHelper do
  require Logger
  alias Chain.EVM.Notification

  def spawn_notification_handler(pid, socket_ref) do
    Task.start(fn ->
      handle_notification(pid, socket_ref)
    end)
  end

  defp handle_notification(pid, socket_ref) do
    receive do
      %Notification{event: :error, data: err} ->
        send(pid, {:error, err, socket_ref})

      %Notification{event: :started, data: data} ->
        send(pid, {:started, data, socket_ref})

      other ->
        Logger.debug("Unknown message from chain #{inspect(other)}")
    end
  end
end
