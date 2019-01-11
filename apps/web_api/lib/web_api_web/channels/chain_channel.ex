defmodule WebApiWeb.ChainChannel do
  require Logger

  use Phoenix.Channel, log_join: false, log_handle_in: :debug
  alias Chain.Snapshot.Details, as: SnapshotDetails

  # Handle someone joined chain
  def join("chain:" <> _chain_id, _, socket) do
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
  def handle_in(
        "take_snapshot",
        params,
        %{topic: "chain:" <> id} = socket
      ) do
    case Chain.take_snapshot(id) do
      {:ok, %SnapshotDetails{} = details} ->
        snapshot = %{
          id: id,
          snapshot_id: Map.get(details, :id),
          chain_type: Map.get(details, :chain),
          download_url: "/snapshot/#{Map.get(details, :id)}"
        }

        if description = Map.get(params, "description") do
          Chain.SnapshotManager.store(%SnapshotDetails{details | description: description})
        end

        {:reply, {:ok, %{snapshot: snapshot}}, socket}

      {:error, err} ->
        {:reply, {:error, %{message: err}}, socket}
    end
  end

  # Revert snapshot for chain
  def handle_in(
        "revert_snapshot",
        %{"snapshot" => snapshot_id},
        %{topic: "chain:" <> id} = socket
      ) do
    with %SnapshotDetails{} = snapshot <- Chain.SnapshotManager.by_id(snapshot_id),
         :ok <- Chain.revert_snapshot(id, snapshot) do
      {:reply, {:ok, %{status: "ok"}}, socket}
    else
      err ->
        Logger.error("#{id}: Failed to revert snapshot: #{inspect(err)}")
        {:reply, {:error, %{message: "failed to revert snapshot"}}, socket}
    end
  end
end
