defmodule Cli.Chain do

  @doc """
  Start interactive shell that will collect all needed vars and start new chain
  """
  @spec start_interactive() :: none()
  def start_interactive() do
    IO.puts("\nStarting new chain")

    type =
      "What chain type do you want [#{Cli.selected("geth")}|ganache]:"
      |> Cli.promt("geth")

    db_path =
      "Please provide path for chain data (Example: /tmp/test):"
      |> Cli.promt!()

    http_port =
      "Your HTTP JSONRPC port [#{Cli.selected("8545")}]:"
      |> Cli.promt("8545")

    ws_port =
      if type == "geth" do
        "Your WS JSONRPC port [#{Cli.selected("8546")}]:"
        |> Cli.promt("8546")
      else
        "8545"
      end

    output =
      "Path where to store EVM logs [#{Cli.selected("empty")}]:"
      |> Cli.promt()

    automine =
      "Do you need automining [y|#{Cli.selected("n")}]:"
      |> Cli.promt("n")

    accounts =
      "How many accounts do you need to create [#{Cli.selected("1")}]:"
      |> Cli.promt("1")

    config = %Chain.EVM.Config{
      db_path: db_path,
      type: String.to_atom(type),
      http_port: String.to_integer(http_port),
      ws_port: String.to_integer(ws_port),
      output: output,
      automine: automine == "y",
      accounts: String.to_integer(accounts)
    }

    {:ok, id} = Chain.start(config)
    IO.puts("\nYour chain ID is: #{id}")
  end
end
