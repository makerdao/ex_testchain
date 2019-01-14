defmodule Storage.Provider do
  @doc """
  Store given chain details in DB.
  Idea is very simple you have to pass chain config as 1st arg, status as 2nd and any other required info
  as 3rd (if you need it.)

  Everything will be merged in one big map and stored in BD.
  """
  @callback store(record :: %{id: binary, status: atom()}) :: :ok | {:error, term()}

  @doc """
  Remove chain details from DB by chain id
  """
  @callback remove(id :: binary) :: :ok | {:error, term()}

  @doc """
  Load list of chains available in DB
  """
  @callback list() :: [%{id: binary, status: atom()}]

  @doc """
  Load chain details by chain id
  """
  @callback get(id :: binary) :: nil | %{id: binary, status: atom()} | {:error, term()}

  @doc """
  Default child spec for starting provider
  """
  @callback child_spec() :: :supervisor.child_spec()
end
