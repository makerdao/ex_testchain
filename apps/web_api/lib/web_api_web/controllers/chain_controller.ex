defmodule WebApiWeb.ChainController do
  use WebApiWeb, :controller

  # Get version for binaries and chain
  def version(conn, _) do
    conn
    |> text(Chain.version())
  end
end
