defmodule Cli.Main do
  @commands %{
    "start" => "Interactive shell for starting chains",
    "exit" => "Exit from ex_testchain",
    "help" => "Prints this help message",
    "mine_start" => "Start mining for chain ID",
    "mine_stop" => "Stop mining for chain ID",
    "make_snapshot" => "Make snaphot for chain"
  }

  @switches [
    help: :boolean,
    version: :boolean,
    start: :boolean,
    type: :string,
    datadir: :string,
    accounts: :integer,
    rpcport: :integer,
    wsport: :integer,
    out: :string,
    networkid: :integer,
    id: :integer,
    automine: :boolean
  ]

  @aliases [
    h: :help,
    v: :version,
    s: :start,
    t: :type,
    a: :accounts
  ]

  def main(args) do
    args
    |> parse_args()
    |> process_args()
  end

  def parse_args(args) do
    {params, _, _} = OptionParser.parse(args, aliases: @aliases, switches: @switches)

    params
    |> Enum.into(%{})
  end

  def process_args(%{help: true}) do
    print_help_message()
  end

  def process_args(%{version: true}) do
    print_version_message()
  end

  def process_args(%{start: true} = config) do
    %Chain.EVM.Config{
      type: Map.get(config, :type, "geth") |> String.to_atom(),
      id: Map.get(config, :id),
      http_port: Map.get(config, :rpcport, 8545),
      ws_port: Map.get(config, :wsport, 8546),
      network_id: Map.get(config, :networkid, 999),
      db_path: Map.get(config, :datadir, ""),
      accounts: Map.get(config, :accounts, 1),
      output: Map.get(config, :out, ""),
      automine: Map.get(config, :automine, false),
      notify_pid: self()
    }
    |> Cli.Chain.start()

    receive_command()
  end

  def process_args(_) do
    print_interactive_help_message()
    receive_command()
  end

  defp receive_command do
    IO.gets("\n> ")
    |> String.trim()
    |> String.downcase()
    |> String.split(" ")
    |> execute_command
  end

  defp execute_command(["exit"]), do: IO.puts("\nExiting...")
  defp execute_command(["quit"]), do: IO.puts("\nQuiting...")

  defp execute_command(["start"]) do
    Cli.Chain.start_interactive()
    receive_command()
  end

  defp execute_command(["help"]) do
    print_interactive_help_message()
    receive_command()
  end

  defp execute_command(["mine_start"]) do
    Cli.Chain.mine_start("")
    receive_command()
  end

  defp execute_command(["mine_start", id]) do
    Cli.Chain.mine_start(id)
    receive_command()
  end

  defp execute_command(["mine_stop"]) do
    Cli.Chain.mine_start("")
    receive_command()
  end

  defp execute_command(["mine_stop", id]) do
    Cli.Chain.mine_stop(id)
    receive_command()
  end

  defp execute_command(["take_snapshot"]) do
    Cli.Chain.take_snapshot("", "")
    receive_command()
  end

  defp execute_command(["take_snapshot", id]) do
    Cli.Chain.take_snapshot(id, "")
    receive_command()
  end

  defp execute_command(["take_snapshot", id, path]) do
    Cli.Chain.take_snapshot(id, path)
    receive_command()
  end

  defp execute_command(_unknown) do
    IO.puts("\nInvalid command. I don't know what to do.")
    print_interactive_help_message()

    receive_command()
  end

  defp print_help_message do
    """
    ExTestchain is project that will help you to work with a local testchains.

    Without any option CLI will start in interactive mode and will print help there.

    List of available commands:

     -h|--help      Shows this help message
     -v|--version   Shows CLI tools versions and all other version info for system
     -s|--start     Start new chain and enter interactive mode.

    Start new chain:

    To start new chain use `-s --datadir=/some/dir` options.
    Example: 

      #{Cli.selected("./cli -s --datadir=/tmp/test")}

    Other start options:

      -t|--type       Chain type. Available options are: [geth|ganache] (default: geth)
      -a|--accounts   Amount of account needed to create on chain start (default: 1)
      --datadir       Data directory for the chain databases and keystore
      --rpcport       HTTP-RPC server listening port (default: 8545)
      --wsport        WS-RPC server listening port (default: 8546)
      --out           File where all chain logs will be streamed
      --networkid     Network identifier (integer, 1=Frontier, 2=Morden (disused), 3=Ropsten, 4=Rinkeby) (default: 999)
      --automine      Enable mining (default: disabled)

    After starting new chain system will enter interactive mode.
    Where you can type #{Cli.selected("help")} for getting help.
    """
    |> IO.puts()
  end

  defp print_interactive_help_message do
    IO.puts(IO.ANSI.yellow() <> "\nWelcome to ex_testchain interactive mode !" <> IO.ANSI.reset())
    IO.puts("\nWe supports following commands:\n")

    @commands
    |> Enum.map(fn {command, description} ->
      IO.puts("  #{IO.ANSI.yellow()}#{command}#{IO.ANSI.reset()} - #{description}")
    end)
  end

  defp print_version_message() do
    {:ok, cli} = :application.get_key(:cli, :vsn)

    """
    CLI version: #{to_string(cli)}
    Chain app version: #{Chain.version()}
    """
    |> IO.puts()
  end
end
