defmodule Cli.Main do
  @commands %{
    "exit" => "Exit from ex_testchain",
    "start" => "Interactive shell for starting chains"
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
    IO.puts("Welcome to the ex_testchain project!")
    print_help_message()
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

  defp execute_command(_unknown) do
    IO.puts("\nInvalid command. I don't know what to do.")
    print_help_message()

    receive_command()
  end

  defp print_help_message do
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
