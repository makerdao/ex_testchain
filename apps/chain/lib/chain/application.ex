defmodule Chain.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      Chain.EVM.Supervisor,
      {Registry, keys: :unique, name: Chain.EVM.Registry}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
