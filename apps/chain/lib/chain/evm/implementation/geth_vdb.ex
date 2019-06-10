defmodule Chain.EVM.Implementation.GethVDB do
  @moduledoc """
  Geth Vulcanize version EVM implementation
  This is exactly same `geth` version with 2 differences:
   - It compiled manually into `evm` image
   - It requires additional starting flag `--gcmode=archive`

  Note that because it's compiled manually path to binary may have to be configured
  """
  use Chain.EVM

  alias Chain.EVM.Config
  alias Chain.EVM.Account
  alias Chain.EVM.Implementation.Geth.Genesis
  alias Chain.EVM.Implementation.Geth.AccountsCreator

  require Logger

  @impl Chain.EVM
  def start(%Config{id: id, db_path: db_path} = config) do
    # We have to create accounts only if we don't have any already
    accounts =
      case Storage.AccountStore.exists?(db_path) do
        false ->
          Logger.debug("#{id}: Creating accounts")

          config
          |> Map.get(:accounts)
          |> AccountsCreator.create_accounts(db_path)
          |> store_accounts(db_path)

        true ->
          Logger.info("#{id} Path #{db_path} is not empty. New accounts would not be created.")
          {:ok, list} = load_accounts(db_path)
          list
      end

    Logger.debug("#{id}: Accounts: #{inspect(accounts)}")

    unless File.exists?(Path.join(db_path, "genesis.json")) do
      :ok = write_genesis(config, accounts)
      Logger.debug("#{id}: genesis.json file created")
    end

    # Checking for existing genesis block and init if not found
    # We switched to --dev with instamining feature so right now
    # we don't need to init chain from genesis.json

    unless File.dir?(db_path <> "/geth") do
      :ok = init_chain(db_path)
    end

    Logger.debug("#{id}: starting port with geth node")

    case start_node(config, accounts) do
      %{err: nil} = port ->
        {:ok, %{port: port, mining: true}}

      other ->
        {:error, other}
    end
  end

  @impl Chain.EVM
  def stop(_, %{port: port} = state) do
    send_command(port, "exit")
    {:ok, state}
  end

  @impl Chain.EVM
  def terminate(id, config, nil) do
    Logger.error("#{id} could not start process... Something wrong. Config: #{inspect(config)}")
    :ok
  end

  @impl Chain.EVM
  def terminate(id, _config, state) do
    Logger.debug("#{id}: Terminating... #{inspect(state)}")
    # Porcelain.Process.stop(port)
    :ok
  end

  @impl Chain.EVM
  def version() do
    %{err: nil, status: 0, out: out} = Porcelain.shell("#{executable!()} version")
    out
  end

  @impl Chain.EVM
  def executable!(),
    do: Application.get_env(:chain, :geth_vdb_executable)

  @doc """
  Bootstrap and initialize a new genesis block.

  It will run `geth init` command using `--datadir db_path`
  """
  @spec init_chain(binary) :: :ok | {:error, term()}
  def init_chain(db_path) do
    %{status: status, err: nil} =
      "#{executable!()} --datadir #{db_path} init #{db_path}/genesis.json 2>/dev/null"
      |> Porcelain.shell()

    case status do
      0 ->
        Logger.debug("#{__MODULE__} geth initialized chain in #{db_path}")
        :ok

      code ->
        Logger.error("#{__MODULE__}: Failed to run `geth init`. exited with code: #{code}")
        {:error, :init_failed}
    end
  end

  @doc """
  Start geth node based on given parameters
  """
  @spec start_node(Chain.EVM.Config.t(), [Chain.EVM.Account.t()]) :: Porcelain.Process.t()
  def start_node(config, accounts) do
    Porcelain.spawn_shell(build_command(config, accounts), out: {:send, self()})
  end

  @doc """
  Execute special console command on started node.
  Be default command will be executed using HTTP JSONRPC console.

  Comamnd will be used:
  `geth --exec "${command}" attach http://localhost:${http_port}`

  Example:
  ```elixir
  iex()> Chain.EVM.Implementation.Geth.exec_command(8545, "eth_blockNumber")
  {:ok, 80}
  ```
  """
  @spec exec_command(binary | non_neg_integer(), binary, term()) ::
          {:ok, term()} | {:error, term()}
  def exec_command(http_port, command, params \\ nil)
      when is_binary(http_port) or is_integer(http_port) do
    "http://localhost:#{http_port}"
    |> JsonRpc.call(command, params)
  end

  #
  # Private functions
  #

  # Writing `genesis.json` file into defined `db_path`
  defp write_genesis(
         %Config{db_path: db_path, id: id} = config,
         accounts
       ) do
    Logger.debug("#{id}: Writring genesis file to `#{db_path}/genesis.json`")

    %Genesis{
      chain_id: Map.get(config, :network_id, 999),
      accounts: accounts,
      gas_limit: Map.get(config, :gas_limit),
      period: Map.get(config, :block_mine_time, 0)
    }
    |> Genesis.write(db_path)
  end

  # Build argument list for new geth node. See `Chain.EVM.Geth.start_node/1`
  defp build_command(
         %Config{
           db_path: db_path,
           network_id: network_id,
           http_port: http_port,
           ws_port: ws_port,
           output: output,
           gas_limit: gas_limit
         },
         accounts
       ) do
    [
      executable!(),
      "--gcmode=archive",
      "--datadir #{db_path}",
      "--networkid #{network_id}",
      # Changing default network port to be able to start on one machine
      "--port=30302",
      # Disabling network, node is private !
      "--maxpeers=0",
      "--nousb",
      "--ipcdisable",
      "--mine",
      "--minerthreads=1",
      "--rpc",
      "--rpcport #{http_port}",
      "--rpcapi admin,personal,eth,miner,debug,txpool,net,web3,db,ssh",
      "--rpcaddr=\"0.0.0.0\"",
      "--rpccorsdomain=\"*\"",
      "--rpcvhosts=\"*\"",
      "--ws",
      "--wsport #{ws_port}",
      "--wsorigins=\"*\"",
      "--gasprice=\"2000000000\"",
      "--targetgaslimit=\"#{gas_limit}\"",
      "--password=#{AccountsCreator.password_file()}",
      get_etherbase(accounts),
      get_unlock(accounts),
      "console",
      get_output(output)
    ]
    |> Enum.join(" ")
  end

  #####
  # List of functions generating CLI options
  #####

  # combine list of accounts to unlock `--unlock 0x....,0x.....`
  defp get_unlock([]), do: ""

  defp get_unlock(list) do
    res =
      list
      |> Enum.map(fn %Account{address: address} -> address end)
      |> Enum.join("\",\"")

    "--unlock=\"#{res}\""
  end

  # get etherbase account. it's just 1st address from list
  defp get_etherbase([]), do: ""

  defp get_etherbase([%Account{address: address} | _]),
    do: "--etherbase=#{address}"

  # Get path for logging
  defp get_output(""), do: "2>> /dev/null"
  defp get_output(path) when is_binary(path), do: "2>> #{path}"
  # Ignore in any other case
  defp get_output(_), do: "2>> /dev/null"

  #####
  # End of list
  #####

  # Send command to port
  # This action will send command directly to started node console.
  # Without attaching.
  # If you will send breacking command - node might exit

  defp send_command(port, command) do
    Porcelain.Process.send_input(port, command <> "\n")
    :ok
  end
end
