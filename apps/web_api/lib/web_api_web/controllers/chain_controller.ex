defmodule WebApiWeb.ChainController do
  use WebApiWeb, :controller

  alias Chain.SnapshotManager

  # Get version for binaries and chain
  def version(conn, _) do
    conn
    |> text(Chain.version())
  end

  # Load snapshot detailt and download file
  def download_snapshot(conn, %{"id" => id}) do
    with %{path: path} <- SnapshotManager.by_id(id),
         true <- File.exists?(path) do
      conn
      |> send_download({:file, path})
    else
      _ ->
        conn
        |> put_status(404)
        |> put_view(WebApiWeb.ErrorView)
        |> render("404.json")
    end
  end

  # load list of snapshots for chain
  def snapshot_list(conn, %{"chain" => chain}) do
    list =
      chain
      |> String.to_atom()
      |> SnapshotManager.by_chain()

    conn
    |> json(%{status: 0, list: list})
  end

  # Remove chain details from internal storage
  def remove_chain(conn, %{"id" => id}) do
    with false <- Chain.alive?(id),
         :ok <- Chain.clean(id) do
      conn
      |> put_status(200)
      |> json(%{status: 0, message: "Chain data will be deleted"})
    else
      true ->
        conn
        |> put_status(400)
        |> put_view(WebApiWeb.ErrorView)
        |> render("400.json", message: "Chain is operational. please stop it first")

      _ ->
        conn
        |> put_status(500)
        |> put_view(WebApiWeb.ErrorView)
        |> render("500.json", message: "Something wrong on removing chain")
    end
  end

  # Load chain details for running chain
  def details(conn, %{"id" => id}) do
    with {:ok, info} <- Chain.details(id) do
      conn
      |> json(%{status: 0, details: info})
    end
  end
end
