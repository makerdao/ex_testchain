defmodule ChainTest do
  use ExUnit.Case
  doctest Chain

  test "greets the world" do
    assert Chain.hello() == :world
  end
end
