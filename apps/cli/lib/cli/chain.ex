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

    {:ok, id} = Chain.start(config)

    "Your chain ID is #{Cli.selected(id)}.\n"
    |> IO.puts()

    # Timeout feature
    # Chain will start or message will be received with timeout
    Process.send_after(self(), :timeout, @timeout)

    [
      frames: :bouncing_ball,
      text: "Loading chain...",
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
