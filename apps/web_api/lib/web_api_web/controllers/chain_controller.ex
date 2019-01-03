defmodule WebApiWeb.ChainController do
  use WebApiWeb, :controller

  alias Chain.SnapshotManager
  alias Chain.Snapshot.Details

  # Get version for binaries and chain
  def version(conn, _) do
    conn
    |> text(Chain.version())
  end

  # Load snapshot detailt and download file
  def download_snapshot(conn, %{"id" => id}) do
    with %{path: path} <- SnapshotManager.details(id),
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
end
