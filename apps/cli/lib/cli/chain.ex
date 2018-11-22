defmodule Cli.Chain do
  @timeout Application.get_env(:chain, :kill_timeout)

  @doc """
  Start interactive shell that will collect all needed vars and start new chain
  """
  @spec start_interactive() :: none()
  def start_interactive() do
    IO.puts("\n#{IO.ANSI.yellow()}Starting new chain.#{IO.ANSI.reset()}\n")

    type =
      "What chain type do you want [#{Cli.selected("geth")}|ganache]: "
      |> Cli.promt("geth")

    db_path =
      "Please provide path for chain data (Example: /tmp/test): "
      |> Cli.promt!()

    http_port =
      "Your HTTP JSONRPC port [#{Cli.selected("8545")}]: "
      |> Cli.promt("8545")

    ws_port =
      if type == "geth" do
        "Your WS JSONRPC port [#{Cli.selected("8546")}]: "
        |> Cli.promt("8546")
      else
        "8545"
      end

    output =
      "Path where to store EVM logs [#{Cli.selected("empty")}]: "
      |> Cli.promt()

    automine =
      "Do you need automining [y|#{Cli.selected("n")}]: "
      |> Cli.promt("n")

    accounts =
      "How many accounts do you need to create [#{Cli.selected("1")}]: "
      |> Cli.promt("1")

    config = %Chain.EVM.Config{
      db_path: db_path,
      type: String.to_atom(type),
      http_port: String.to_integer(http_port),
      ws_port: String.to_integer(ws_port),
      output: output,
      automine: automine == "y",
      accounts: String.to_integer(accounts),
      notify_pid: self()
    }

    start(config)
  end

  @doc """
  Start new chain using existing configs
  """
  @spec start(Chain.EVM.Config.t()) :: term()
  def start(%Chain.EVM.Config{db_path: ""}) do
    (IO.ANSI.light_red() <>
       "Please provide --datadir=/some/path to start new chain" <> IO.ANSI.reset())
    |> IO.puts()

    System.halt(1)
  end

  def start(%Chain.EVM.Config{type: type} = config) do
    {:ok, id} = Chain.start(config)

    "Starting new #{Cli.selected(to_string(type))} chain with ID : #{Cli.selected(id)}.\n"
    |> IO.puts()

    # Timeout feature
    # Chain will start or message will be received with timeout
    Process.send_after(self(), :timeout, @timeout)

    [
      frames: :dots,
      text: "Setting up your chain...",
      done: " "
    ]
    |> CliSpinners.spin_fun(fn ->
      receive do
        %Chain.EVM.Process{} = process ->
          print_result(process)

        :timeout ->
          IO.puts("Seems something went wrong...")

        _ ->
          Cli.error("Something wrong...")
      end
    end)

    # Base return value
    {:ok, id}
  end

  @doc """
  Start mining process for selected chain
  Usage: 

      iex> Cli.Chain.mine_start("4942249475330991771")

  Will print error in case of something wrong
  """
  @spec mine_start(binary) :: none()
  def mine_start("") do
    """
    #{IO.ANSI.light_red()}Usage #{IO.ANSI.underline()}mine_start your_chain_id#{IO.ANSI.reset()}
    """
    |> IO.puts()
  end

  def mine_start(id) do
    try do
      :ok =
        id
        |> Chain.start_mine()

      "#{IO.ANSI.yellow()}Mining started for chain #{id}#{IO.ANSI.reset()}"
      |> IO.puts()
    rescue
      _ ->
        print_no_chain()
    end
  end

  @doc """
  Stop mining process for selected chain
  Usage: 

      iex> Cli.Chain.mine_stop("4942249475330991771")

  Will print error in case of something wrong
  """
  @spec mine_stop(binary) :: none()
  def mine_stop("") do
    """
    #{IO.ANSI.light_red()}Usage `mine_stop your_chain_id` #{IO.ANSI.reset()}
    """
    |> IO.puts()
  end

  def mine_stop(id) do
    try do
      :ok =
        id
        |> Chain.stop_mine()

      "#{IO.ANSI.yellow()}Mining stopped for chain #{id}#{IO.ANSI.reset()}"
      |> IO.puts()
    rescue
      _ ->
        print_no_chain()
    end
  end

  @doc """
  Takes snapshot for chain
  Usage: 

      iex> Cli.Chain.take_snapshot("4942249475330991771", "/path/to/snapshot")

  Will print error in case of something wrong
  """
  @spec take_snapshot(binary, binary) :: none()
  def take_snapshot("", _) do
    """
    #{IO.ANSI.light_red()}Usage `take_snapshot your_chain_id /path/to/snapshot` #{IO.ANSI.reset()}
    """
    |> IO.puts()
  end

  def take_snapshot(_, "") do
    """
    #{IO.ANSI.light_red()}Usage `take_snapshot your_chain_id /path/to/snapshot` #{IO.ANSI.reset()}
    """
    |> IO.puts()
  end

  def take_snapshot(id, path) do
    try do
      {:ok, snapshot} = Chain.take_snapshot(id, path)

      "#{IO.ANSI.light_yellow()}Snapshot was taken to #{snapshot} for chain #{id}#{
        IO.ANSI.reset()
      }"
      |> IO.puts()
    rescue
      err ->
        IO.inspect(err)
        print_no_chain()
    end
  end

  @doc """
  Restores snapshot for chain
  Usage: 

      iex> Cli.Chain.revert_snapshot("4942249475330991771", "/path/to/snapshot")

  Will print error in case of something wrong
  """
  @spec revert_snapshot(binary, binary) :: none()
  def revert_snapshot("", _) do
    """
    #{IO.ANSI.light_red()}Usage `revert_snapshot your_chain_id /path/to/snapshot` #{
      IO.ANSI.reset()
    }
    """
    |> IO.puts()
  end

  def revert_snapshot(_, "") do
    """
    #{IO.ANSI.light_red()}Usage `revert_snapshot your_chain_id /path/to/snapshot` #{
      IO.ANSI.reset()
    }
    """
    |> IO.puts()
  end

  def revert_snapshot(id, path) do
    try do
      :ok = Chain.revert_snapshot(id, path)

      "#{IO.ANSI.light_yellow()}Snapshot was restored from #{path} for chain #{id}#{
        IO.ANSI.reset()
      }"
      |> IO.puts()
    rescue
      err ->
        IO.inspect(err)
        print_no_chain()
    end
  end

  defp print_no_chain do
    "#{IO.ANSI.red()}No such chain found. Sorry...#{IO.ANSI.reset()}"
    |> IO.puts()
  end

  defp print_result(%Chain.EVM.Process{} = result) do
    """
    \n\n#{IO.ANSI.yellow()}Your chain is ready to work !#{IO.ANSI.reset()}
    #{Cli.comment("============================================================")}
    #{format_row("Chain ID", Map.get(result, :id))}
    #{format_row("RPC URL", Map.get(result, :rpc_url))}
    #{format_row("WS URL", Map.get(result, :ws_url))}
    #{format_row("Coinbase address", Map.get(result, :coinbase))}
    #{Cli.comment("------------------------------------------------------------")}
    #{IO.ANSI.cyan()}Accounts available:#{IO.ANSI.reset()}
    #{format_accounts(Map.get(result, :accounts, []))}
    """
    |> IO.puts()
  end

  defp format_row(title, value) do
    [
      IO.ANSI.cyan(),
      String.pad_trailing(title, 20),
      ":",
      IO.ANSI.reset(),
      "  ",
      IO.ANSI.green(),
      IO.ANSI.underline(),
      value,
      IO.ANSI.reset()
    ]
    |> Enum.join()
  end

  defp format_accounts(accounts) do
    accounts
    |> Enum.map(&" - #{IO.ANSI.yellow()}#{IO.ANSI.underline()}#{&1}#{IO.ANSI.reset()}\n")
  end
end
