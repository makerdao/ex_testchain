defmodule Chain.EVM.Implementation.Ganache do
  @moduledoc """
  Ganache EVM implementation
  """
  use Chain.EVM

  alias Chain.EVM.Config

  @ganache_cli Path.absname("../../priv/presets/ganache/node_modules/.bin/ganache-cli")
  @wrapper_file Path.absname("../../priv/presets/ganache/wrapper.sh")

  @impl Chain.EVM
  def start(%Config{id: id} = config) do
    unless File.exists?(@ganache_cli) do
      raise "No `ganache-cli` installed. Please run `cd priv/presets/ganache && npm install`"
    end

    file = open_log_file(config)

    Logger.debug("#{id}: Starting ganache-cli")
    port = start_node(config)
    {:ok, %{port: port, id: id, config: config, mining: true, log_file: file}}
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
  def handle_msg(_str, %{log_file: nil}), do: :ok

  def handle_msg(str, %{log_file: file}) do
    IO.binwrite(file, str)
    :ok
  end

  @impl Chain.EVM
  def take_snapshot(
        _,
        %{id: id, config: %{http_port: http_port}, mining: mining} = state
      ) do
    Logger.debug("#{id}: Making snapshot")

    case exec_command(http_port, "evm_snapshot") do
      {:ok, snapshot_id} ->
        Logger.debug("#{id} Snapshot made with id #{snapshot_id}")
        {:reply, {:ok, snapshot_id}, state}

      _ ->
        Logger.error("#{id}: Failed to make snapshot")
        {:reply, {:error, :unknown}, state}
    end
  end

  @impl Chain.EVM
  def revert_snapshot(
        <<"0x", _::binary>> = snapshot,
        %{id: id, config: %{http_port: http_port}} = state
      ) do
    Logger.debug("#{id} Reverting snapshot #{snapshot}")

    case exec_command(http_port, "evm_revert", snapshot) do
      {:ok, true} ->
        Logger.debug("#{id} Snapshot #{snapshot} reverted")
        {:reply, :ok, state}

      _ ->
        Logger.error("#{id}: Failed to revert snapshot #{snapshot}")
        {:reply, {:error, :unknown}, state}
    end
  end

  def revert_snapshot(_, state), do: {:reply, {:error, :wrong_snapshot_id}, state}

  @impl Chain.EVM
  def terminate(%{port: port, id: id, log_file: file}) do
    Logger.info("#{id}: Terminating...")
    Porcelain.Process.stop(port)

    unless file == nil do
      Logger.debug("#{id} Closing log file")
      File.close(file)
    end

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
  defp get_output(""), do: "--quiet 2>/dev/null"
  # We don't need to pipe stream because of we wrapped everything using `wrapper.sh` file
  defp get_output(path) when is_binary(path), do: "--verbose 2>/dev/null"
  # Ignore in any other case
  defp get_output(_), do: "--quiet 2>/dev/null"

  # Build command for starting ganache-cli
  defp build_command(%Config{
         db_path: db_path,
         network_id: network_id,
         http_port: http_port,
         accounts: accounts,
         output: output
       }) do
    [
      # Sorry but this **** never works as you expect so I have to wrap it into "killer" script
      # Otherwise after application will be terminated - ganache still will be running
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

  # Opens file if it should be opened to store logs from ganache
  # Function should get `Chain.EVM.Config.t()` as input
  defp open_log_file(%Config{output: ""}), do: nil

  defp open_log_file(%Config{id: id, output: path}) when is_binary(path) do
    Logger.debug("#{id}: Opening file #{path} for writing logs")
    {:ok, file} = File.open(path, [:binary, :append])
    file
  end

  defp open_log_file(_), do: nil
end
