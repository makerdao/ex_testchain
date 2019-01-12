defmodule WebApi.ChainMessageHandler do
  @moduledoc """
  Main process that will handle all messages from different chains.
  Because this process will have name all communication to it should be
  done using it's name, to avoid restart and change pid issue.
  """
  use GenServer

  require Logger
  alias Chain.EVM.Notification

  @table :listeners

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc false
  def init(_) do
    :ets.new(@table, [:duplicate_bag, :protected, :named_table])
    {:ok, []}
  end

  # Add new event listener with socket_ref
  def handle_cast({:add, id, event, pid, socket_ref}, state) do
    true = :ets.insert(@table, {id, event, pid, socket_ref})
    {:noreply, state}
  end

  # Handle Notification from chain
  def handle_info(%Notification{id: id, event: event, data: data}, state) do
    # Check if we have direct requests for handler
    # Note :ets will return result as [[pid, socket_ref]]
    @table
    |> :ets.match({id, event, :"$1", :"$2"})
    |> Enum.each(fn [pid, socket_ref] ->
      send(pid, {event, data, socket_ref})
      # removing from list
      :ets.delete_object(@table, {id, event, pid, socket_ref})
    end)

    # Broadcasting event to direct channel
    response =
      case data do
        %_{} ->
          Map.from_struct(data)

        %{} ->
          data

        other ->
          %{data: other}
      end

    if event in [:started, :error] do
      WebApiWeb.Endpoint.broadcast("api", to_string(event), response)
    end

    WebApiWeb.Endpoint.broadcast("chain:#{id}", to_string(event), response)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @doc """
  Add new socket pid with socket ref to list of event listeners.
  On event happening `WebApi.ChainMessageHandler` will send message to given `pid`
  with such content: `{event, data, socket_ref}`
  So you have to handle this message !
  """
  @spec notify_on(
          Chain.evm_id(),
          Chain.EVM.Notification.event(),
          pid,
          Phoenix.Channel.socket_ref()
        ) :: :ok
  def notify_on(id, event, pid, socket_ref),
    do: GenServer.cast(__MODULE__, {:add, id, event, pid, socket_ref})
end
