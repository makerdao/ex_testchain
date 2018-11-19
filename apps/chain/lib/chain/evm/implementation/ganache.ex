defmodule Chain.EVM.Implementation.Ganache do
  @moduledoc """
  Ganache EVM implementation
  """
  use Chain.EVM

  alias Chain.EVM.Config

  @ganache_cli Path.absname("../../priv/presets/ganache/node_modules/.bin/ganache-cli")
  @wrapper_file Path.absname("../../wrapper.sh")

  @impl Chain.EVM
  def start(%Config{db_path: ""}), do: {:error, "Wrong db_path. Please define it."}

  def start(%Config{id: id, db_path: db_path} = config) do
    unless File.exists?(@ganache_cli) do
      raise "No `ganache-cli` installed. Please run `cd priv/presets/ganache && npm install`"
    end

    unless File.dir?(db_path) do
      Logger.debug("#{id}: #{db_path} not exist, creating...")
      :ok = File.mkdir_p!(db_path)
    end

    Logger.debug("#{id}: Starting ganache-cli")
    port = start_node(config)
    {:ok, %{port: port, id: id, config: config, mining: true}}
  end

  @impl Chain.EVM
  def stop(%{port: port} = state) do
    true = Porcelain.Process.stop(port)
    {:ok, state}
  end

  @impl Chain.EVM
  def start_mine(%{config: %Config{http_port: http_port}} = state) do
    {:ok, true} = exec_command(http_port, "miner_start")
    {:ok, %{state | mining: true}}
  end

  @impl Chain.EVM
  def stop_mine(%{config: %Config{http_port: http_port}} = state) do
    {:ok, true} = exec_command(http_port, "miner_stop")
    {:ok, %{state | mining: false}}
  end

  @impl Chain.EVM
  def take_snapshot(
        _,
        %{id: id, config: %{http_port: http_port}, mining: mining} = state
      ) do
    Logger.debug("#{id}: Making snapshot")

    if mining do
      Logger.debug("#{id}: Stopping mining before taking snapshot")
      stop_mine(state)
    end

    {:ok, snapshot_id} = exec_command(http_port, "evm_snapshot")
    Logger.debug("#{id} Snapshot made with id #{snapshot_id}")

    if mining do
      Logger.debug("#{id}: Starting mining after taking snapshot")
      start_mine(state)
    end

    {:reply, {:ok, snapshot_id}, state}
  end

  @impl Chain.EVM
  def revert_snapshot(
        <<"0x", _::binary>> = snapshot,
        %{id: id, config: %{http_port: http_port}} = state
      ) do
    Logger.debug("#{id} Reverting snapshot #{snapshot}")

    {:ok, true} = exec_command(http_port, "evm_revert", snapshot)
    Logger.debug("#{id} Snapshot #{snapshot} reverted")
    {:reply, {:ok, snapshot}, state}
  end

  def revert_snapshot(_, state), do: {:reply, {:error, :wrong_snapshot_id}, state}

  @impl Chain.EVM
  def terminate(%{port: port, id: id} = state) do
    Logger.info("#{id}: Terminating... #{inspect(state)}")
    Porcelain.Process.stop(port)
    :ok
  end

  @impl Chain.EVM
  def version() do
    %{err: nil, status: 0, out: out} = Porcelain.shell("#{@ganache_cli} --version")
    out
  end

  @doc """
  Starting new ganache node based on given config
  """
  @spec start_node(Chain.EVM.Config.t()) :: Porcelain.Process.t()
  def start_node(config) do
    Porcelain.spawn_shell(build_command(config), out: {:send, self()})
  end

  @doc """
  Execute special console command on started node.
  Be default command will be executed using `seth rpc` command.

  Comamnd will be used: 
  `seth  --rpc-url localhost:${http_port} prc ${command}`

  Example: 
  ```elixir
  iex()> Chain.EVM.Implementation.Ganache.exec_command(8545, "eth_blockNumber")
  %Porcelain.Result{err: nil, out: "80\n", status: 0} 
  ```
  """
  @spec exec_command(binary | non_neg_integer(), binary, term()) :: Porcelain.Result.t()
  def exec_command(http_port, command, params \\ nil)
      when is_binary(http_port) or is_integer(http_port) do
    "http://localhost:#{http_port}"
    |> JsonRpc.call(command, params)
  end

  # Get path for logging
  defp get_output(""), do: "2>/dev/null"
  defp get_output(path) when is_binary(path), do: "2>#{path}"
  # Ignore in any other case
  defp get_output(_), do: "2>/dev/null"

  # Build command for starting ganache-cli
  defp build_command(%Config{
         db_path: db_path,
         network_id: network_id,
         http_port: http_port,
         accounts: accounts,
         output: output
       }) do
    [
      # Sorry but this **** never works as you expect so I have to wrap it into "killer"
      # Otherwise after application will be terminated - ganache still wwill be running
      @wrapper_file,
      @ganache_cli,
      "--noVMErrorsOnRPCResponse",
      "-i #{network_id}",
      "-p #{http_port}",
      "-a #{accounts}",
      "--db #{db_path} ",
      get_output(output)
    ]
    |> Enum.join(" ")
  end
end
