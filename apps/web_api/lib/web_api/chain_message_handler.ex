defmodule WebApi.ChainMessageHandler do
  @moduledoc """
  Main process that will handle all messages from different chains.
  Because this process will have name all communication to it should be
  done using it's name, to avoid restart and change pid issue.
  """
  use GenServer

  alias Chain.EVM.Notification

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc false
  def init(_), do: {:ok, %{}}

  # Add new event listener with socket_ref
  def handle_cast({:add, event, pid, socket_ref}, state) do
    list = Map.get(state, event, [])

    case Enum.member?(list, pid) do
      true ->
        {:noreply, state}

      false ->
        new_state = Map.put(state, event, list ++ [{pid, socket_ref}])
        {:noreply, new_state}
    end
  end

  # Handle Notification from chain
  def handle_info(%Notification{id: id, event: event, data: data}, state) do
    # Check if we have direct requests for handler
    if (list = Map.get(state, event, [])) && list != [] do
      list
      |> Enum.each(fn {pid, socket_ref} -> send(pid, {event, data, socket_ref}) end)
    end

    # Broadcasting event to direct channel
    Phoenix.Endpoint.broadcast("chain:#{id}", event, data)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.inspect(msg)
    {:noreply, state}
  end

  @doc """
  Add new socket pid with socket ref to list of event listeners.
  On event happening `WebApi.ChainMessageHandler` will send message to given `pid`
  with such content: `{event, data, socket_ref}`
  So you have to handle this message !
  """
  @spec notify_on(Chain.EVM.Notification.event(), pid, Phoenix.Channel.socket_ref()) :: :ok
  def notify_on(event, pid, socket_ref),
    do: GenServer.cast(__MODULE__, {:add, event, pid, socket_ref})
end
