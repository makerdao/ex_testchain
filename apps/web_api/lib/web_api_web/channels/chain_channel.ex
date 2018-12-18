defmodule WebApiWeb.ChainChannel do
  use Phoenix.Channel, log_join: false, log_handle_in: :debug

  # Handle someone joined chain
  def join("chain:" <> chain_id, _, socket) do
    # case Chain.exist?(chain_id) do
    #   true ->
    #     {:ok, socket}

    #   false ->
    #     {:error, %{reason: "chain does not exist"}}
    # end
    {:ok, socket}
  end

  # Stop chain
  def handle_in("stop", _, %{topic: "chain:" <> id} = socket) do
    :ok = Chain.stop(id)
    {:reply, :ok, socket}
  end

  # Take snapshot for chain
  def handle_in("take_snapshot", _, %{topic: "chain:" <> id} = socket) do
    case Chain.take_snapshot(id) do
      {:ok, path} ->
        {:reply, {:ok, %{snapshot: path}}, socket}

      {:error, err} ->
        {:reply, {:error, %{message: err}}, socket}
    end
  end

  # Revert snapshot for chain
  def handle_in("revert_snapshot", %{"snapshot" => path}, %{topic: "chain:" <> id} = socket) do
    case Chain.revert_snapshot(id, path) do
      :ok ->
        {:reply, {:ok, %{status: "ok"}}, socket}

      {:error, err} ->
        {:reply, {:error, %{message: err}}, socket}
    end
  end
end
