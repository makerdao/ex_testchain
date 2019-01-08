defmodule ChainTest do
  use ExUnit.Case
  doctest Chain

  alias Chain.EVM.Config

  describe "start() :: " do
    test "fail with non existing chain" do
      {:error, :unsuported_evm_type} =
        %Config{type: :non_existing}
        |> Chain.start()
    end
  end
end
