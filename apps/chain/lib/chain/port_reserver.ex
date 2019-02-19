defmodule Chain.PortReserver do
  @moduledoc """
  This module will watch chains and reserve resources for them.
  In case new chain is started and allocated ports/folder it should send message
  to this module. And module will remember it and will allocate ports/folder
  under chain PID. 
  In case of chain PID stops watcher will automatically free this resources.

  Actually work of this module is just store ports, folders under ETS table 
  and watching for chain pids for failures/termination.

  PortReserver will be automatically called by `Chain.EVM` module

  Usage: 

      Chain.PortReserver.reserve(8545)

  PortReserver stores everything in one ETS table in format: 
  `{port, owner_pid}`

  Where `pid` - is chain process id that will be watched by `Chain.PortReserver` module

  Another idea after the watcher is solving restart on snapshot issue. 
  For example if we have one chain running on port `8545`. And try to make a snapshot,
  we have to stop chain, copy all files to snapshot folder and start chain again.
  But there might be a situation when another chain will start to start on same port
  and because 1st one will be stopped 2nd one will occupy port. 
  So 1st chain wouldn't be able to start after snapshot.

  Same situation might be for path.
  """
  use GenServer

  # ETS table name for watcher module
  @table :chain_watcher

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init([]) do
    :ets.new(@table, [:set, :protected, :named_table])
    {:ok, []}
  end

  @doc false
  def handle_call({:reserve, port}, {from, _}, []) do
    :ets.insert(@table, {port, from})
    Process.monitor(from)
    {:reply, :ok, []}
  end

  @doc false
  def handle_call(:new_unused_port, from, []) do
    port =
      :chain
      |> Application.get_env(:evm_port_range, 8500..8600)
      |> Enum.random()

    case :ets.lookup(@table, port) do
      [] ->
        # Reserving port
        {:reply, :ok, []} = handle_call({:reserve, port}, from, [])
        {:reply, port, []}

      _ ->
        handle_call(:new_unused_port, from, [])
    end
  end

  @doc false
  def handle_call({:port_in_use, port}, _from, []) do
    case :ets.lookup(@table, port) do
      [] ->
        {:reply, false, []}

      _ ->
        {:reply, true, []}
    end
  end

  # Handle process termination
  # See `Process.monitor/1` for more info
  def handle_info({:DOWN, _ref, :process, pid, _}, []) do
    case :ets.match(@table, {:"$1", pid}) do
      [] ->
        {:noreply, []}

      list ->
        list
        |> List.flatten()
        |> Enum.each(&:ets.delete(@table, &1))

        {:noreply, []}
    end
  end

  @doc """
  Add process that called this function into watch list. and reserve http/ws ports and 
  chain db path into PortReserver. 
  After process dies - watcher will release locks from port/path.
  """
  @spec reserve(pos_integer()) :: :ok | {:error, term()}
  def reserve(port),
    do: GenServer.call(__MODULE__, {:reserve, port})

  @doc """
  Will generate new unused port and reserve it with callee pid
  """
  @spec new_unused_port() :: pos_integer()
  def new_unused_port(),
    do: GenServer.call(__MODULE__, :new_unused_port)

  @doc """
  Check if given port is in use 
  """
  @spec port_in_use?(pos_integer()) :: boolean
  def port_in_use?(port), do: GenServer.call(__MODULE__, {:port_in_use, port})
end
