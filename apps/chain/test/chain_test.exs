defmodule ChainTest do
  use ExUnit.Case
  doctest Chain

  alias Chain.EVM.Config

  test "start() fail with non existing chain" do
    {:error, :unsuported_evm_type} =
      %Config{type: :non_existing}
      |> Chain.start()
  end

  test "unique_id() to get uniq numbers" do
    refute Chain.unique_id() == Chain.unique_id()
  end

  test "version() to get versions" do
    assert Chain.version() =~ "version"
  end
end
