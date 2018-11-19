defmodule Cli.Chain.Interactive do
  @help """
  This will be help
  """

  @doc """
  Start interactive mode for one chain with given ID
  """
  @spec start(binary) :: none()
  def start(""),
    do:
      IO.puts(
        "#{IO.ANSI.red()}Failed to start interactive mode for empty chain ID#{IO.ANSI.reset()}"
      )

  def start(id) do
    """

    #{IO.ANSI.light_yellow()}Started interactive mode for chain #{Cli.selected(id)}#{
      IO.ANSI.reset()
    }
    """
    |> IO.puts()

    receive_command(id)
  end

  defp execute_command(["h"], id), do: execute_command(["help"], id)

  defp execute_command(["help"], _id) do
    @help
    |> IO.puts()
  end

  defp execute_command(["stop"], id) do
    Chain.stop(id)

    """
    #{IO.ANSI.yellow()}Chain #{id} has been stopped.#{IO.ANSI.reset()} 
    """
    |> IO.puts()

    :exit
  end

  defp execute_command(["mine_start"], id) do
    Cli.Chain.mine_start(id)
  end

  defp execute_command(["mine_stop"], id) do
    Cli.Chain.mine_stop(id)
  end

  defp execute_command(["take_snapshot"], id) do
    Cli.Chain.take_snapshot(id, "")
  end

  defp execute_command(["take_snapshot", path], id) do
    Cli.Chain.take_snapshot(id, path)
  end

  defp execute_command(command, _id) do
    IO.puts("Unknown command passed #{List.first(command)}")
  end

  # Command receiver
  defp receive_command(:exit), do: ""

  defp receive_command(id) do
    res =
      IO.gets("\n#{id} > ")
      |> String.trim()
      |> String.downcase()
      |> String.split(" ")
      |> execute_command(id)

    # Handling command result.
    # If we got `:exit` atom we should exit interactive loop
    # Otherwose looping for same id
    case res do
      :exit ->
        IO.puts("Exiting interactive mode for chain #{id}...")

      _ ->
        receive_command(id)
    end
  end
end
