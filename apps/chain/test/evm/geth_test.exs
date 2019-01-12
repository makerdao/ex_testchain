defmodule Chain.EVM.GethTest do
  use Chain.Test.EVMTestCase, chain: :geth, timeout: 30_000
end
