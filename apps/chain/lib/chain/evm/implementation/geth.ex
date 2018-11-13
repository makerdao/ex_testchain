defmodule Chain.EVM.Implementation.Geth do
  @moduledoc """
  Geth EVM implementation
  """
  use Chain.EVM

  alias Chain.EVM.Config
  alias Chain.EVM.Implementation.Geth.Genesis

  require Logger

  @password_file Path.absname("../../priv/presets/geth/account_password")

  @impl Chain.EVM
  def start(%Config{db_path: ""}), do: {:error, "Wrong db_path. Please define it."}

  def start(%Config{id: id, db_path: db_path} = config) do
    unless File.exists?(db_path) do
      Logger.debug("#{id}: #{db_path} not exist, creating...")
      :ok = File.mkdir_p!(db_path)
    end

    Logger.debug("#{id}: Creating accounts")
    accounts = create_accounts(Map.get(config, :accounts), db_path)
    Logger.debug("#{id}: Accounts created: #{inspect(accounts)}")

    unless File.exists?(db_path <> "/genesis.json") do
      :ok = write_genesis(config, accounts)
      Logger.debug("#{id}: genesis.json file created")
    end

    # Checking for existing genesis block and init if not found
    unless File.dir?(db_path <> "/geth") do
      :ok = init_chain(db_path)
    end

    Logger.debug("#{id}: starting port with geth node")
    port = start_node(config, accounts)

    {:ok, %{port: port, id: id, config: config, accounts: accounts, mining: false}}
  end

  @impl Chain.EVM
  def stop(%{port: port} = state) do
    send_command(port, "exit")
    {:ok, state}
  end

  @impl Chain.EVM
  def started?(%{config: %{http_port: http_port}}) do
    case exec_command(http_port, "eth_coinbase") do
      {:ok, <<"0x", _::binary>>} ->
        true

      _ ->
        false
    end
  end

  @impl Chain.EVM
  def handle_started(%{id: id, config: %{notify_pid: pid, automine: mine}} = state) do
    Logger.warn("#{id}: Everything loaded...")
    result = combine_result(state)

    if mine do
      start_mine(state)
    end

    send(pid, result)
    {:ok, %{state | mining: mine}}
  end

  @impl Chain.EVM
  def handle_msg(str, %{id: id} = state) do
    Logger.info("#{id}: #{str}")
    {:ok, state}
  end

  @impl Chain.EVM
  def start_mine(%{config: %Config{http_port: http_port}} = state) do
    {:ok, res} = exec_command(http_port, "miner_start", 1)
    IO.inspect res
    {:ok, %{state | mining: true}}
  end

  @impl Chain.EVM
  def stop_mine(%{config: %Config{http_port: http_port}} = state) do
    {:ok, res} = exec_command(http_port, "miner_stop")
    IO.inspect res
    {:ok, %{state | mining: false}}
  end

  @impl Chain.EVM
  def take_snapshot(
        path_to,
        %{id: id, config: %{db_path: db_path}, mining: mining} = state
      ) do
    Logger.debug("#{id}: Making snapshot")

    unless File.dir?(path_to) do
      :ok = File.mkdir_p!(path_to)
    end

    if mining do
      Logger.debug("#{id}: Stopping mining before taking snapshot")
      stop_mine(state)
    end

    {:ok, _} = File.cp_r(db_path, path_to)
    Logger.debug("#{id}: Snapshot made to #{path_to}")

    if mining do
      Logger.debug("#{id}: Starting mining after taking snapshot")
      start_mine(state)
    end

    :ok
  end

  @impl Chain.EVM
  def terminate(%{port: port, id: id} = state) do
    Logger.info("#{id}: Terminating... #{inspect(state)}")
    Porcelain.Process.stop(port)
    :ok
  end

  @doc """
  Create new account for geth

  Will create new account with password from file `Path.absname("../../priv/presets/geth/account_password")`
  using `geth account new` command.

  Example: 
  ```elixir
  iex(1)> Chain.EVM.Geth.create_account("/path/to/chain/data/dir")
  "172536bfde649d20eaf4ac7a3eab742b9a6cc373"
  ```
  """
  @spec create_account(binary) :: {:ok, term()} | {:error, term()}
  def create_account(db_path) do
    %{status: 0, err: nil, out: <<"Address: {", address::binary-size(40), _::binary>>} =
      "#{executable!()} account new --datadir #{db_path} --password #{@password_file} 2>/dev/null"
      |> Porcelain.shell()

    address
  end

  @doc """
  Create `amount` of new accounts.

  Example:
  ```elixir
  iex> Chain.EVM.Geth.create_accounts(3, System.user_home!())
  ["21371d54056b10fab95e1babdc61a3ebc584dce9",
  "608c6e2cd12a1f59180083283e6c3600526b3485",
  "c3e1a2ed30439792ce5d63b13342a22931220f41"]
  ```
  """
  @spec create_accounts(non_neg_integer(), binary) :: [binary]
  def create_accounts(amount, db_path) when amount >= 1 do
    1..amount
    |> Enum.map(fn _ -> create_account(db_path) end)
  end

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
  @spec start_node(Chain.EVM.Config.t(), [Chain.account()]) :: Porcelain.Process.t()
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
  @spec exec_command(binary | non_neg_integer(), binary, term()) :: Porcelain.Result.t()
  def exec_command(http_port, command, params \\ nil)
      when is_binary(http_port) or is_integer(http_port) do
    "http://localhost:#{http_port}"
    |> JsonRpc.call(command, params)
  end

  @doc """
  Load list of existing accounts existing in chain

  Example: 
  ```elixir
  iex()> Chain.EVM.Implementation.Geth.list_accounts(8545)
  ["0x603a0993495dd494f1b6dbbcef8d1f9d7fe170e0",
    "0x62161e957c53bfba349ab853ad31211e4df1c9f9",
    "0xf9fe5d779726c9dd9fd19d1f27c0f29a13432d37",
    "0xe21f7b35be07d761645f5aca91ddc1dad781f606"]
  ```
  """
  @spec list_accounts(non_neg_integer() | binary) :: {:ok, [binary]} | {:error, term()}
  def list_accounts(http_port) do
    {:ok, list} = exec_command(http_port, "eth_accounts")

    list
  end

  #
  # Private functions
  #

  # Get executable path
  defp executable!() do
    case System.find_executable("geth") do
      nil ->
        throw("No executable 'geth' found in system...")

      path ->
        Logger.debug("Found executable #{path}")
        path
    end
  end

  # Combine everything
  defp combine_result(%{id: id, config: config}) do
    http_port = Map.get(config, :http_port)

    {:ok, address} = exec_command(http_port, "eth_coinbase")
    {:ok, accounts} = exec_command(http_port, "eth_accounts")

    %Chain.EVM.Process{
      id: id,
      coinbase: address,
      accounts: accounts,
      rpc_url: "http://localhost:#{http_port}",
      ws_url: "ws://localhost:#{Map.get(config, :ws_port)}"
    }
  end

  # Writing `genesis.json` file into defined `db_path`
  defp write_genesis(%Config{db_path: db_path, network_id: chain_id, id: id}, accounts) do
    Logger.debug("#{id}: Writring genesis file to `#{db_path}/genesis.json`")

    %Genesis{
      chain_id: chain_id,
      accounts: accounts
    }
    |> Genesis.write(db_path)
  end

  # get first created account. it will be coinbase
  defp get_account([{account, _} | _]), do: account
  defp get_account([account | _]) when is_binary(account), do: account

  # Get path for logging
  defp get_output(""), do: "2>> /dev/null"
  defp get_output(path) when is_binary(path), do: "2>> #{path}"
  # Ignore in any other case
  defp get_output(_), do: "2>> /dev/null"

  # Build argument list for new geth node. See `Chain.EVM.Geth.start_node/1`
  defp build_command(
         %Config{
           db_path: db_path,
           network_id: network_id,
           http_port: http_port,
           ws_port: ws_port,
           output: output
         },
         accounts
       ) do
    [
      executable!(),
      "--datadir",
      db_path,
      "--networkid",
      network_id |> to_string(),
      "--ipcdisable",
      "--rpc",
      "--rpcport",
      http_port |> to_string(),
      "--rpcapi",
      "admin,personal,eth,miner,debug,txpool,net",
      "--ws",
      "--wsport",
      ws_port |> to_string(),
      "--wsorigins=\"*\"",
      # "--mine",
      # "--minerthreads=1",
      "--etherbase=\"0x#{get_account(accounts)}\"",
      "console",
      get_output(output)
    ]
    |> Enum.join(" ")
  end

  # Send command to port
  # This action will send command directly to started node console.
  # Without attaching. 
  # If you will send breacking command - node might exit
  defp send_command(port, command) do
    Porcelain.Process.send_input(port, command <> "\n")
    :ok
  end
end
