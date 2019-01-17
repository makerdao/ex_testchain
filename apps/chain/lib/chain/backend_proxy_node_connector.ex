defmodule Chain.BackendProxyNodeConnector do
  @moduledoc """
  This module is responsible for connecting to QA backend service
  Because that service will be written with Elixir too we are using 
  internal `Node.connect/1` function for managing communication.

  In case of disconnect we have to run timer for reconnect.
  """
  use GenServer

  require Logger

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  def init(_) do
    case connect() do
      true ->
        {:ok, true}

      false ->
        {:ok, false, timeout()}
    end
  end

  @doc false
  def handle_info({:nodedown, _}, _connected) do
    Logger.warn(fn -> "#{__MODULE__}: Disconnected from backend node #{backend_node()}" end)

    Node.monitor(backend_node(), false)

    case connect() do
      true ->
        {:noreply, true}

      false ->
        {:noreply, false, timeout()}
    end
  end

  @doc false
  def handle_info(:timeout, _connected) do
    case connect() do
      true ->
        {:noreply, true}

      false ->
        {:noreply, false, timeout()}
    end
  end

  @doc false
  def terminate(_, true), do: Node.monitor(backend_node(), false)
  # def terminate(_, _), do: :normal

  # Try connecting to node
  defp connect() do
    case Node.connect(backend_node()) do
      true ->
        Logger.debug("#{__MODULE__}: Connected to backend  service node #{backend_node()}")
        Node.monitor(backend_node(), true, [:allow_passive_connect])
        true

      _ ->
        # Logger.debug("#{__MODULE__}: Failed to connect to #{backend_node()}")
        false
    end
  end

  # get node address where we need to connect
  defp backend_node(), do: Application.get_env(:chain, :backend_proxy_node)

  # Timeout generation for reconnect
  defp timeout(),
    do: Application.get_env(:chain, :backend_proxy_node_reconnection_timeout, 10_000)
end
