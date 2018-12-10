defmodule Chain.Watcher do
  @moduledoc """
  This module will watch chains and reserv resources for them.
  In case new chain is started and allocated ports/folder it should send message
  to this module. And module will remember it and will allocate ports/folder
  under chain PID. 
  In case of chain PID stops watcher will automatically free this resources.

  Actually work of this module is just store ports, folders under ETS table 
  and watching for chain pids for failures/termination.

  Watcher will be automatically called by `Chain.EVM` module

  Usage: 

      Chain.Watcher.watch(8545, 8546, "/var/chains/somechain"})

  Watcher stores everything in one ETS table in format: 
  `{pid, http_port, ws_port, db_path}` 

  Where `pid` - is chain process id that will be watched by `Chain.Watcher` module

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
  def handle_call({:watch, http, ws, db}, {from, _}, []) do
    case :ets.insert(@table, {from, http, ws, db}) do
      true ->
        Process.monitor(from)
        {:reply, :ok, []}

      _ ->
        {:reply, {:error, "failed to insert"}, []}
    end
  end

  # Handle process termination
  # See `Process.monitor/1` for more info
  def handle_info({:DOWN, _ref, :process, pid, _}, []) do
    :ets.delete(@table, pid)
    {:noreply, []}
  end

  @doc """
  Add process that called this function into watch list. and reserve http/ws ports and 
  chain db path into Watcher. 
  After process dies - watcher will release locks from port/path.
  """
  @spec watch(pos_integer() | nil, pos_integer() | nil, binary) :: :ok | {:error, term()}
  def watch(http_port, ws_port, db_path) do
    GenServer.call(__MODULE__, {:watch, http_port, ws_port, db_path})
  end

  @doc """
  Check if given port is in use 
  """
  @spec port_in_use?(pos_integer()) :: boolean
  def port_in_use?(port) do
    case :ets.select(@table, by_port(port)) do
      [] ->
        false

      _ ->
        true
    end
  end

  @doc """
  Check if path is in use
  """
  @spec path_in_use?(binary) :: boolean
  def path_in_use?(path) do
    case :ets.match(@table, {:"$1", :_, :_, path}) do
      [] ->
        false

      _ ->
        true
    end
  end

  # Default select query for ETS table that will get record where http_port or ws_port
  # equals to given
  # This query looks really weired so take a look into `:ets.fun2ms/1` for better understanding
  defp by_port(port) do
    [
      {{:_, :"$1", :"$2", :_}, [{:orelse, {:==, :"$1", port}, {:==, :"$2", port}}], [:"$_"]}
    ]
  end
end
