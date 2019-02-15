defmodule Chain.EVM.Implementation.Ganache do
  @moduledoc """
  Ganache EVM implementation
  """
  use Chain.EVM

  alias Chain.EVM.Account
  alias Chain.EVM.Config

  @impl Chain.EVM
  def start(%Config{id: id, accounts: amount, db_path: db_path} = config) do
    Logger.debug("#{id}: Starting ganache-cli")

    accounts =
      case Storage.AccountStore.exists?(db_path) do
        false ->
          amount
          |> generate_accounts()
          |> store_accounts(db_path)

        true ->
          {:ok, list} = load_accounts(db_path)
          list
      end

    %{err: nil} = port = start_node(config, accounts)

    file = open_log_file(config)

    {:ok, %{port: port, log_file: file}}
  end

  @impl Chain.EVM
  def stop(%{id: id}, %{port: port} = state) do
    Logger.debug("#{id}: Stoping ganache evm")
    true = Porcelain.Process.stop(port)
    {:ok, state}
  end

  @impl Chain.EVM
  def handle_msg(_str, _, %{log_file: nil}), do: :ok

  @impl Chain.EVM
  def handle_msg(str, _, %{log_file: file}), do: IO.binwrite(file, str)

  @impl Chain.EVM
  def terminate(id, _config, %{port: port, log_file: file}) do
    Logger.debug("#{id}: Terminating...")

    if Porcelain.Process.alive?(port) do
      Porcelain.Process.stop(port)
    end

    unless file == nil do
      Logger.debug("#{id} Closing log file")
      File.close(file)
    end

    :ok
  end

  def terminate(id, config, nil) do
    Logger.error("#{id} could not start process... Something wrong. Config: #{inspect(config)}")
    :ok
  end

  @impl Chain.EVM
  def version() do
    %{err: nil, status: 0, out: out} = Porcelain.shell("#{executable!()} --version")
    out
  end

  @impl Chain.EVM
  def executable!(), do: Application.get_env(:chain, :ganache_executable)

  @doc """
  Starting new ganache node based on given config
  """
  @spec start_node(Chain.EVM.Config.t(), [Chain.EVM.Account.t()]) :: Porcelain.Process.t()
  def start_node(config, accounts) do
    config
    |> build_command(accounts)
    |> Porcelain.spawn_shell(out: {:send, self()})
  end

  @doc """
  Execute special console command on started node.
  Be default command will be executed using `seth rpc` command.

  Comamnd will be used: 
  `seth  --rpc-url localhost:${http_port} prc ${command}`

  Example: 
  ```elixir
  iex()> Chain.EVM.Implementation.Ganache.exec_command(8545, "eth_blockNumber")
  {:ok, "0x000000000000000000000000000"}
  ```
  """
  @spec exec_command(binary | non_neg_integer(), binary, term()) ::
          {:ok, term()} | {:error, term()}
  def exec_command(http_port, command, params \\ nil)
      when is_binary(http_port) or is_integer(http_port) do
    "http://localhost:#{http_port}"
    |> JsonRpc.call(command, params)
  end

  # Build command for starting ganache-cli
  defp build_command(
         %Config{
           db_path: db_path,
           network_id: network_id,
           http_port: http_port,
           output: output,
           block_mine_time: block_mine_time,
           gas_limit: gas_limit
         },
         accounts
       ) do
    wrapper_file =
      :chain
      |> Application.get_env(:ganache_wrapper_file)
      |> Path.absname()

    unless File.exists?(wrapper_file) do
      raise "No wrapper file for ganache-cli: #{wrapper_file}"
    end

    [
      # Sorry but this **** never works as you expect so I have to wrap it into "killer" script
      # Otherwise after application will be terminated - ganache still will be running
      wrapper_file,
      executable!(),
      "--noVMErrorsOnRPCResponse",
      "-i #{network_id}",
      "-p #{http_port}",
      "--db #{db_path}",
      "--gasLimit #{gas_limit}",
      inline_accounts(accounts),
      get_block_mine_time(block_mine_time),
      get_output(output)
    ]
    |> Enum.join(" ")
  end

  defp generate_accounts(number) do
    0..number
    |> Enum.map(fn _ -> Account.new() end)
  end

  defp inline_accounts(accounts) do
    accounts
    |> Enum.map(fn %Account{priv_key: key, balance: balance} ->
      "--account=\"0x#{key},#{balance}\""
    end)
    |> Enum.join(" ")
  end

  #####
  # List of functions generating CLI options
  #####

  # get params for block mining period
  defp get_block_mine_time(0), do: ""

  defp get_block_mine_time(time) when is_integer(time) and time > 0,
    do: "--blockTime #{time}"

  defp get_block_mine_time(_), do: ""

  # Get path for logging
  defp get_output(""), do: "--quiet 2>/dev/null"
  # We don't need to pipe stream because of we wrapped everything using `wrapper.sh` file
  defp get_output(path) when is_binary(path), do: "--verbose 2>/dev/null"
  # Ignore in any other case
  defp get_output(_), do: "--quiet 2>/dev/null"

  #####
  # End of list 
  #####

  # Opens file if it should be opened to store logs from ganache
  # Function should get `Chain.EVM.Config.t()` as input
  defp open_log_file(%Config{output: ""}), do: nil

  defp open_log_file(%Config{id: id, output: path}) when is_binary(path) do
    Logger.debug("#{id}: Opening file #{path} for writing logs")
    {:ok, file} = File.open(path, [:binary, :append])
    file
  end
end
