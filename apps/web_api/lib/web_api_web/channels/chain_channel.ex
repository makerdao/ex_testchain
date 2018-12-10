defmodule WebApiWeb.ChainChannel do
  use Phoenix.Channel

  def join("chain:" <> chain_id, _, socket) do
    {:ok, socket}
  end
end
