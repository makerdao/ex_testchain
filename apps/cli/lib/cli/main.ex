defmodule Cli.Main do
  @commands %{
    "exit" => "Exit from ex_testchain",
    "start" => "Interactive shell for starting chains"
  }

  def main(args) do
    args
    |> parse_args()
    |> process_args()
  end

  def parse_args(args) do
    {params, _, _} = OptionParser.parse(args, switches: [help: :boolean, version: :boolean])
    params
  end

  def process_args(help: true) do
    print_help_message()
  end

  def process_args(version: true) do
    print_version_message()
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
