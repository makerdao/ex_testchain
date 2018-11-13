defmodule JsonRpc do
  @moduledoc """
  Very simple Ethereum JSONRPC client 
  For now only HTTP implementation and not all functions
  Used only for internal commands
  """

  alias JsonRpc.HttpApi

  @spec eth_accounts(binary) :: {:ok, term()} | {:error, term()}
  def eth_accounts(url), do: call(url, "eth_accounts")

  @spec eth_coinbase(binary) :: {:ok, term()} | {:error, term()}
  def eth_coinbase(url), do: call(url, "eth_coinbase")

  @spec miner_start(binary, non_neg_integer()) :: {:ok, term()} | {:error, term()}
  def miner_start(url, threads \\ 1), do: call(url, "miner_start", threads)

  @spec miner_stop(binary) :: {:ok, term()} | {:error, term()}
  def miner_stop(url), do: call(url, "miner_stop")

  @doc """
  Make an RPC call to given URL
  """
  @spec call(binary, binary, term()) :: {:ok, term()} | {:error, term()}
  def call(url, method, params \\ nil), do: HttpApi.send(url, method, params)
end
