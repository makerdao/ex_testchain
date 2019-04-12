defmodule Storage.AccountStore do
  @moduledoc """
  Account storage modules.
  It will store list of account for chain with their private keys
  """

  # file where list of initial accounts will be stored
  @file_name "initial_addresses"

  @doc """
  Store list of accounts into `{db_path}/addresses.json` file
  """
  @spec store(binary, [map]) :: :ok | {:error, term()}
  def store(db_path, list) do
    db_path
    |> Path.join(@file_name)
    |> File.write(:erlang.term_to_binary(list))
  end

  @doc """
  Load list of initial accounts from chain `{db_path}/accounts.json`
  """
  @spec load(binary) :: {:ok, [map]} | {:error, term()}
  def load(db_path) do
    file = Path.join(db_path, @file_name)

    with true <- File.exists?(file),
         {:ok, content} <- File.read(file),
         res <- :erlang.binary_to_term(content, [:safe]) do
      {:ok, res}
    else
      _ ->
        {:error, "failed to load addresses from #{db_path}"}
    end
  end

  @doc """
  Checks if file with list of accounts exist
  """
  @spec exists?(binary) :: boolean()
  def exists?(db_path) do
    db_path
    |> Path.join(@file_name)
    |> File.exists?()
  end
end
