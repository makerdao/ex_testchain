defmodule Chain.EVM.Implementation.Geth.AccountsCreator do
  @moduledoc """
  Module handles all work related to accounts creation for geth
  """
  alias Chain.EVM.Account
  alias Chain.EVM.Implementation.Geth

  use GenServer

  require Logger

  @timeout 60_000

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, [])

  @doc false
  def init(_), do: {:ok, nil}

  @doc """
  Handle poolboy account creating
  """
  def handle_call({:create_account, db_path}, _from, state) do
    case create(db_path) do
      {:ok, account} ->
        {:reply, account, state}

      {:error, err} ->
        Logger.error("Failed to create account: #{inspect(err)}")
        {:reply, nil, state}
    end
  end

  ##############
  #
  # Client functions
  #
  ##############

  @doc """
  Create new account for geth

  Will create new account using: 
   - newly generated private key
   - password from file configured in `Application.get_env(:chain, :geth_password_file)`
   - `db_path` given as an input argument

  It will use `geth account import` command.

  Example: 
  ```elixir
  iex(1)> Chain.EVM.Implementation.Geth.AccountsCreator.create("/path/to/chain/data/dir")
  {:ok,
    %Chain.EVM.Account{
      address: "2398855adc701ddc91e5213f7f8dcc928530b431",
      balance: 100000000000000000000,
      priv_key: "15f79c36228a73d5bcad4a3f669dec8b2d2268821edf7c2344cb7a999b15d044"
    }}
  ```
  """
  @spec create(binary) :: {:ok, Chain.EVM.Account.t()} | {:error, term()}
  def create(db_path) do
    %Account{priv_key: key} = account = Account.new()
    priv_file = Path.join(db_path, key)

    with :ok <- File.write(priv_file, key),
         {:ok, _address} <- execute(db_path, priv_file),
         _ <- File.rm(priv_file) do
      {:ok, account}
    else
      _ ->
        # have to recheck if priv key file still exist
        if File.exists?(priv_file) do
          File.rm(priv_file)
        end

        {:error, "something wrong on generating new geth account with priv file"}
    end
  end

  @doc """
  Geth path to existing password file for geth account generation
  """
  @spec password_file() :: binary
  def password_file(), do: Application.get_env(:chain, :geth_password_file)

  @doc """
  Configuration for poolboy
  """
  @spec poolboy_config() :: list()
  def poolboy_config() do
    [
      {:name, {:local, :worker}},
      {:worker_module, __MODULE__},
      {:size, 2},
      {:max_overflow, 2}
    ]
  end

  @doc """
  Create `number` of accounts for geth using poolboy
  """
  @spec create_accounts(non_neg_integer(), binary) :: [Chain.EVM.Accounts.t()]
  def create_accounts(number, db_path) do
    0..number
    |> Enum.map(fn _ -> async_create(db_path) end)
    |> Enum.map(&Task.await(&1, @timeout * 5))
    |> Enum.reject(&is_nil/1)
  end

  # Wrapper for Task.async + poolboy transaction
  defp async_create(db_path) do
    Task.async(fn ->
      :poolboy.transaction(
        :worker,
        &GenServer.call(&1, {:create_account, db_path}, @timeout),
        @timeout
      )
    end)
  end

  # Executing `geth accoutn import` command with correct params
  defp execute(db_path, priv_file) do
    result =
      "#{Geth.executable!()} account import --datadir #{db_path} --password #{password_file()} #{
        priv_file
      } 2>/dev/null"
      |> Porcelain.shell()

    case result do
      %{status: 0, err: nil, out: <<"Address: {", address::binary-size(40), _::binary>>} ->
        {:ok, address}

      _ ->
        {:error, "error creating new geth account with private key"}
    end
  end
end
