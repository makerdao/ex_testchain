defmodule Chain.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Chain.EVM.Implementation.Geth.AccountsCreator

  require Logger

  def start(_type, _args) do
    check_erlang()

    # List all child processes to be supervised
    children = [
      Chain.BackendProxyNodeConnector,
      Chain.EVM.Supervisor,
      {Registry, keys: :unique, name: Chain.EVM.Registry},
      Chain.Watcher,
      Chain.SnapshotManager,
      :poolboy.child_spec(:worker, AccountsCreator.poolboy_config())
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp check_erlang() do
    if 21 > System.otp_release() |> String.to_integer() do
      Logger.error("Application requires Erlang OTP 21+ !")
    end

    if :lt == Version.compare(System.version(), "1.7.0") do
      Logger.error("Application required Elixir 1.7+ !")
    end
  end
end
