defmodule WebApiWeb.ApiChannel do
  use Phoenix.Channel

  def join(_, _, socket), do: {:ok, %{message: "Welcome to ExTestchain !"}, socket}

  def handle_in("start", payload, socket) do
    IO.inspect payload
    {:reply, {:ok, %{test: 1}}, socket}
  end
end
