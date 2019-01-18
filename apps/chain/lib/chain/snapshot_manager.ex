defmodule Chain.SnapshotManager do
  @moduledoc """
  Module that manages snapshoting by copy/paste chain DB folders.
  It could wrap everything to one archive file
  """

  use GenServer
  require Logger

  alias Chain.Snapshot.Details, as: SnapshotDetails
  alias Porcelain.Result
  alias Storage.SnapshotStore

  @doc false
  def start_link(_) do
    unless System.find_executable("tar") do
      raise "Failed to initialize #{__MODULE__}: No tar executable found in system."
    end

    path =
      Application.get_env(:chain, :snapshot_base_path)
      |> Path.expand()

    unless File.dir?(path) do
      :ok = File.mkdir_p!(path)
    end

    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc false
  def init(_), do: {:ok, nil}

  @doc """
  Create a snapshot and store it into local DB (DETS for now)
  """
  @spec make_snapshot!(binary, Chain.evm_type(), binary) :: Chain.Snapshot.Details.t()
  def make_snapshot!(from, chain_type, description \\ "") do
    Logger.debug("Making snapshot for #{from} with description: #{description}")

    unless File.dir?(from) do
      raise ArgumentError, message: "path does not exist"
    end

    id = generate_snapshot_id()

    to =
      :chain
      |> Application.get_env(:snapshot_base_path)
      |> Path.expand()
      |> Path.join("#{id}.tgz")

    if File.exists?(to) do
      raise ArgumentError, message: "archive #{to} already exist"
    end

    result =
      __MODULE__
      |> Task.async(:compress, [from, to])
      |> Task.await()

    case result do
      {:ok, _} ->
        %SnapshotDetails{
          id: id,
          path: to,
          chain: chain_type,
          description: description,
          date: DateTime.utc_now()
        }

      {:error, msg} ->
        raise msg
    end
  end

  @doc """
  Restore snapshot to given path
  """
  @spec restore_snapshot!(Chain.Snapshot.Details.t(), binary) :: :ok
  def restore_snapshot!(nil, _),
    do: raise(ArgumentError, message: "Wrong snapshot details passed")

  def restore_snapshot!(_, ""),
    do: raise(ArgumentError, message: "Wrong snapshot restore path passed")

  def restore_snapshot!(%SnapshotDetails{id: id, path: from}, to) do
    Logger.debug("Restoring snapshot #{id} from #{from} to #{to}")

    unless File.exists?(to) do
      :ok = File.mkdir_p!(to)
    end

    result =
      __MODULE__
      |> Task.async(:extract, [from, to])
      |> Task.await()

    case result do
      {:ok, _} ->
        :ok

      {:error, msg} ->
        raise msg
    end
  end

  @doc """
  Compress given chain folder to `.tgz` archive
  Note: it will compress only content of given dir without full path !
  """
  @spec compress(binary, binary) :: {:ok, binary} | {:error, term()}
  def compress("", _), do: {:error, "Wrong input path"}
  def compress(_, ""), do: {:error, "Wrong output path"}

  def compress(from, to) do
    Logger.debug("Compressing path: #{from} to #{to}")

    command = "tar -czvf #{to} -C #{from} . > /dev/null 2>&1"

    with true <- String.ends_with?(to, ".tgz"),
         false <- File.exists?(to),
         %Result{err: nil, status: 0} <- Porcelain.shell(command, out: nil) do
      {:ok, to}
    else
      false ->
        {:error, "Wrong name (must end with .tgz) for result archive #{to}"}

      true ->
        {:error, "Archive already exist: #{to}"}

      %Result{status: status, err: err} ->
        {:error, "Failed with status: #{inspect(status)} and error: #{inspect(err)}"}

      res ->
        Logger.error(res)
        {:error, "Unknown error"}
    end
  end

  @doc """
  Extracts snapshot to given folder
  """
  @spec extract(binary, binary) :: {:ok, binary} | {:error, term()}
  def extract("", _), do: {:error, "Wrong path to snapshot passed"}
  def extract(_, ""), do: {:error, "Wrong extracting path for snapshot passed"}

  def extract(from, to) do
    Logger.debug("Extracting #{from} to #{to}")

    command = "tar -xzvf #{from} -C #{to} > /dev/null 2>&1"

    unless File.exists?(to) do
      File.mkdir_p(to)
    end

    case Porcelain.shell(command, out: nil) do
      %Result{err: nil, status: 0} ->
        {:ok, to}

      %Result{status: status, err: err} ->
        {:error, "Failed with status: #{inspect(status)} and error: #{inspect(err)}"}
    end
  end

  @doc """
  Store new snapshot into local DB
  """
  @spec store(Chain.Snapshot.Details.t()) :: :ok | {:error, term()}
  def store(%SnapshotDetails{} = snapshot),
    do: SnapshotStore.store(snapshot)

  @doc """
  Load snapshot details by id
  In case of error it might raise an exception
  """
  @spec by_id(binary) :: Chain.Snapshot.Details.t() | nil
  def by_id(id), do: SnapshotStore.by_id(id)

  @doc """
  Load list of existing snapshots by chain type
  """
  @spec by_chain(Chain.evm_type()) :: [Chain.Snapshot.Details.t()]
  def by_chain(chain), do: SnapshotStore.by_chain(chain)

  @doc """
  Remove snapshot details from local DB
  """
  @spec remove(binary) :: :ok
  def remove(id) do
    case by_id(id) do
      nil ->
        :ok

      %SnapshotDetails{path: path} ->
        if File.exists?(path) do
          File.rm(path)
        end

        # Remove from db
        SnapshotStore.remove(id)

        :ok
    end
  end

  # Try to lookup for a key till new wouldn't be generated
  defp generate_snapshot_id() do
    id = Chain.unique_id()

    with nil <- SnapshotStore.by_id(id) do
      id
    else
      _ ->
        generate_snapshot_id()
    end
  end
end
