defmodule Chain.EVM.GanacheTest do
  use Chain.Test.EVMTestCase, chain: :ganache, timeout: 30_000
end
