defmodule Chain.EVM.GanacheTest do
  use ExUnit.Case, async: true

  alias Chain.EVM.Config
  alias Chain.EVM.Notification
  alias Chain.Test.ChainHelper

  alias Chain.Snapshot.Details, as: SnapshotDetails

  @timeout Application.get_env(:chain, :kill_timeout)
  @chain :ganache

  setup_all do
    pid = spawn(&ChainHelper.receive_loop/0)

    ChainHelper.trace(pid)

    config = %Config{
      type: @chain,
      http_port: ChainHelper.rand_port(),
      notify_pid: pid,
      clean_on_stop: true
    }

    {:ok, id} =
      config
      |> Chain.start()

    # Check for receiving notification about chain started
    assert_receive {:trace, ^pid, :receive,
                    %Notification{event: :started, id: ^id, data: data} = notification},
                   @timeout

    assert is_binary(Map.get(data, :rpc_url))
    assert is_binary(Map.get(data, :ws_url))

    ChainHelper.untrace(pid)

    on_exit(fn ->
      ChainHelper.trace(pid)
      :ok = Chain.stop(id)

      assert_receive {:trace, ^pid, :receive,
                      %Notification{id: ^id, event: :status_changed, data: :terminating}},
                     @timeout

      assert_receive {:trace, ^pid, :receive, %Notification{id: ^id, event: :stopped}}, @timeout
      ChainHelper.untrace(pid)

      refute Application.get_env(:chain, :base_path)
             |> Path.join(id)
             |> File.dir?()
    end)

    {:ok, %{id: id, config: config, data: data, pid: pid}}
  end

  test "chain created new chain db", %{id: id} do
    # check for storage
    assert Application.get_env(:chain, :base_path)
           |> Path.join(id)
           |> File.dir?()
  end

  test "take_snapshot/1 should create snapshot and revert_snapshot/2 should restore", %{
    id: id,
    pid: pid
  } do
    assert Chain.exist?(id)

    ChainHelper.trace(pid)
    :ok = Chain.take_snapshot(id)

    assert_receive {:trace, ^pid, :receive,
                    %Notification{id: ^id, event: :snapshot_taken, data: snapshot}},
                   @timeout

    %SnapshotDetails{chain: @chain, path: path} = snapshot
    assert File.exists?(path)

    assert_receive {:trace, ^pid, :receive,
                    %Notification{id: ^id, event: :status_changed, data: :active}},
                   @timeout

    :ok = Chain.revert_snapshot(id, snapshot)

    assert_receive {:trace, ^pid, :receive, %Notification{id: ^id, event: :snapshot_reverted}},
                   @timeout

    assert_receive {:trace, ^pid, :receive,
                    %Notification{id: ^id, event: :status_changed, data: :active}},
                   @timeout

    ChainHelper.untrace(pid)
  end
end