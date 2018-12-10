defmodule WebApi.ChainHelper do

  require Logger
  
  def spawn_notification_handler(pid, socket_ref) do
    Task.start(fn -> 
      handle_notification(pid, socket_ref)
    end)
  end


  defp handle_notification(pid, socket_ref) do
    receive do
      {:error, err} ->
        send(pid, {:error, err, socket_ref})

      {:started, data} ->
        send(pid, {:started, data, socket_ref})

      other ->
        Logger.debug("Unknown message from chain #{inspect(other)}")
    end
  end
end
