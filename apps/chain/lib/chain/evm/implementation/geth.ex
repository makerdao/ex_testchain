defmodule Chain.EVM.Implementation.Geth do
  @moduledoc """
  Geth EVM implementation
  """
  use Chain.EVM

  alias Chain.EVM.Config
  alias Chain.EVM.Notification
  alias Chain.EVM.Implementation.Geth.Genesis

  require Logger

  @impl Chain.EVM
  def start(%Config{id: id, db_path: db_path} = config) do
    # We have to create accounts only if we don't have any already
    accounts =
      case File.ls(db_path) do
        {:ok, []} ->
          Logger.debug("#{id}: Creating accounts")
          create_accounts(Map.get(config, :accounts), db_path)

        _ ->
          Logger.warn("#{id} Path #{db_path} is not empty. New accounts would not be created.")
          {:ok, list} = load_existing_accounts(db_path)
          list
      end

    Logger.debug("#{id}: Accounts: #{inspect(accounts)}")

    unless File.exists?(db_path <> "/genesis.json") do
      :ok = write_genesis(config, accounts)
      Logger.debug("#{id}: genesis.json file created")
    end

    # Checking for existing genesis block and init if not found
    # We switched to --dev with instamining feature so right now 
    # we don't need to init chain from genesis.json

    # unless File.dir?(db_path <> "/geth") do
    # :ok = init_chain(db_path)
    # end

    Logger.debug("#{id}: starting port with geth node")
    %{err: nil} = port = start_node(config, accounts)

    {:ok, %{port: port, accounts: accounts, mining: false}}
  end

  @impl Chain.EVM
  def stop(_, %{port: port} = state) do
    # send_command(port, "exit")
    # Have to stop process usign sigterm
    # otherwise it return bad exit code
    true = Porcelain.Process.stop(port)
    {:ok, state}
  end

  @impl Chain.EVM
  def start_mine(%Config{http_port: http_port}, state) do
    {:ok, nil} = exec_command(http_port, "miner_start", [1])
    {:ok, %{state | mining: true}}
  end

  @impl Chain.EVM
  def stop_mine(%Config{http_port: http_port}, state) do
    {:ok, nil} = exec_command(http_port, "miner_stop")
    {:ok, %{state | mining: false}}
  end

  @impl Chain.EVM
  def take_snapshot(
        path_to,
        %{id: id} = config,
        %{accounts: accounts} = state
      ) do
    Logger.debug("#{id}: Making snapshot")

    db_path = Map.get(config, :db_path)

    unless File.dir?(path_to) do
      Logger.debug("#{id}: Creating new path for snapshot #{path_to}")
      :ok = File.mkdir_p!(path_to)
    end

    # Check if folder is empty
    case File.ls(path_to) do
      {:ok, []} ->
        Logger.debug("#{id} Stopping chain before snapshot")
        {:ok, _} = stop(config, state)

        {:ok, _} = File.cp_r(db_path, path_to)
        Logger.debug("#{id}: Snapshot made to #{path_to}")

        %{err: nil} = port = start_node(config, accounts)
        Logger.debug("#{id} Starting chain after making a snapshot")

        :ok = wait_started(config, state)

        if pid = Map.get(config, :notify_pid) do
          send(pid, %Notification{id: id, event: :snapshot_taken, data: %{path_to: path_to}})
        end

        # Returning spanshot details
        {:reply, {:ok, path_to}, %{state | port: port}}

      _ ->
        {:reply, {:error, "#{path_to} is not empty"}, state}
    end
  end

  @impl Chain.EVM
  def revert_snapshot(path_from, %{id: id} = config, %{accounts: accounts} = state) do
    Logger.debug("#{id} restoring snapshot from #{path_from}")

    db_path = Map.get(config, :db_path)

    case File.dir?(path_from) do
      false ->
        {:reply, {:error, "No such directory #{path_from}"}, state}

      true ->
        Logger.debug("#{id} Stopping chain before restoring snapshot")
        {:ok, _} = stop(config, state)

        if File.dir?(db_path) do
          {:ok, _} = File.rm_rf(db_path)
          :ok = File.mkdir(db_path)
        end

        {:ok, _} = File.cp_r(path_from, db_path)

        %{err: nil} = port = start_node(config, accounts)
        Logger.debug("#{id} Starting chain after restoring a snapshot")

        :ok = wait_started(config, state)
        Logger.debug("#{id} Chain restored snapshot from #{path_from}")

        if pid = Map.get(config, :notify_pid) do
          send(pid, %Notification{
            id: id,
            event: :snapshot_reverted,
            data: %{path_from: path_from}
          })
        end

        # Returning spanshot details
        {:reply, :ok, %{state | port: port}}
    end
  end

  @impl Chain.EVM
  def terminate(id, _config, %{port: port} = state) do
    Logger.info("#{id}: Terminating... #{inspect(state)}")
    Porcelain.Process.stop(port)
    :ok
  end
  def terminate(id, config, nil) do
    Logger.error("#{id} could not start process... Something wrong. Config: #{inspect(config)}")
    :ok
  end

  @impl Chain.EVM
  def version() do
    %{err: nil, status: 0, out: out} = Porcelain.shell("#{executable!()} version")
    out
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
      "#{executable!()} account new --datadir #{db_path} --password #{password_file()} 2>/dev/null"
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
    # TODO: need to use poolboy to create accounts in async worker pools
    # Task.async/await might crash system because of to many `geth` processes at once
    1..amount
    |> Enum.map(fn _ -> create_account(db_path) end)
  end

  def create_accounts(_, _), do: []

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

  #
  # Private functions
  #

  # Get executable path
  defp executable!() do
    case System.find_executable("geth") do
      nil ->
        throw("No executable 'geth' found in system...")

      path ->
        path
    end
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

  # Build argument list for new geth node. See `Chain.EVM.Geth.start_node/1`
  defp build_command(
         %Config{
           db_path: db_path,
           network_id: network_id,
           http_port: http_port,
           ws_port: ws_port,
           output: output,
           block_mine_time: block_mine_time
         },
         accounts
       ) do
    [
      executable!(),
      "--dev",
      "--datadir",
      db_path,
      get_block_mine_time(block_mine_time),
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
      "--gasprice=\"2000000000\"",
      "--targetgaslimit=\"9000000000000\"",
      # "--mine",
      # "--minerthreads=1",
      "--password=#{password_file()}",
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

  # get params for block mining period
  defp get_block_mine_time(0), do: ""

  defp get_block_mine_time(time) when is_integer(time) and time > 0,
    do: "--dev.period=\"#{time}\""

  defp get_block_mine_time(_), do: ""

  # get first created account. it will be coinbase
  defp get_etherbase([]), do: ""
  defp get_etherbase([{account, _} | _]), do: "--etherbase=\"0x#{account}\""
  defp get_etherbase([account | _]) when is_binary(account), do: "--etherbase=\"0x#{account}\""

  # combine list of accounts to unlock `--unlock 0x....,0x.....`
  defp get_unlock([]), do: ""

  defp get_unlock(list) do
    "--unlock=\"" <> Enum.join(list, "\",\"") <> "\""
  end

  # Get path for logging
  defp get_output(""), do: "2>> /dev/null"
  defp get_output(path) when is_binary(path), do: "2>> #{path}"
  # Ignore in any other case
  defp get_output(_), do: "2>> /dev/null"

  #####
  # End of list 
  #####

  # Have to return pasword file for accounts
  defp password_file(), do: Application.get_env(:chain, :geth_password_file)

  # Send command to port
  # This action will send command directly to started node console.
  # Without attaching. 
  # If you will send breacking command - node might exit
  defp send_command(port, command) do
    Porcelain.Process.send_input(port, command <> "\n")
    :ok
  end

  # load list of existing accounts
  defp load_existing_accounts(db_path) do
    case Porcelain.shell("#{executable!()} account list --datadir=#{db_path}") do
      %{err: nil, out: out, status: 0} ->
        {:ok, parse_existing_accounts(out)}

      _ ->
        {:error, "failed to load accounts"}
    end
  end

  defp parse_existing_accounts(list) do
    list
    |> String.split("\n")
    |> Enum.map(&parse_existing_account_line/1)
    |> Enum.reject(&("" == &1))
  end

  defp parse_existing_account_line(""), do: ""

  defp parse_existing_account_line(<<"Account", rest::binary>>) do
    case Regex.named_captures(~r/\{(?<address>.{40})\}/, rest) do
      %{"address" => address} ->
        address

      _ ->
        ""
    end
  end

  # waiting for 30 secs geth to start if not started - raising error
  defp wait_started(config, state, times \\ 0)

  defp wait_started(%{id: id}, _state, times) when times >= 150,
    do: raise("#{id} Timeout waiting geth to start...")

  defp wait_started(config, state, times) do
    case started?(config, state) do
      true ->
        :ok

      _ ->
        # Waiting
        :timer.sleep(200)
        wait_started(config, state, times + 1)
    end
  end
end
