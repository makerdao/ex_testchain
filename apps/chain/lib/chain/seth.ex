defmodule Chain.Seth do
  @moduledoc """
  Default set of `seth` commands.
  """

  require Logger

  @doc """
  Execute `seth rpc` command

  This command may raise error if no `seth` executable will be found in system
  """
  @spec call_rpc(binary, binary) :: Porcelain.Result.t()
  def call_rpc(rpc_url, command) when is_binary(command) do
    Porcelain.shell("#{executable!()} --rpc-url #{rpc_url} rpc #{command}")
  end

  # Get seth executable
  defp executable!() do
    case System.find_executable("seth") do
      nil ->
        raise "No `seth` executable found in system. exiting..."

      path ->
        path
    end
  end
end
