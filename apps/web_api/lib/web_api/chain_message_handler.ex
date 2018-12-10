defmodule WebApi.ChainMessageHandler do
  @moduledoc """
  Main process that will handle all messages from different chains.
  Because this process will have name all communication to it should be
  done using it's name, to avoid restart and change pid issue.
  """
  use GenServer

  alias Chain.EVM.Notification

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc false
  def init(_), do: {:ok, []}

  def handle_info(%Notification{id: id, event: :started, data: data}, state) do
    IO.inspect(id)
    IO.inspect(data)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.inspect(msg)
    {:noreply, state}
  end
end
