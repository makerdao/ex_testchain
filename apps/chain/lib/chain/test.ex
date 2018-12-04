defmodule Chain.Test do
  @moduledoc """
  Module for testing purposes only !
  Will be deleted afterwards
  """

  @base_path "/tmp/chain"

  def config() do
    %Chain.EVM.Config{
      db_path: @base_path,
      output: @base_path <> "/evm.out",
      notify_pid: self()
    }
  end
end
