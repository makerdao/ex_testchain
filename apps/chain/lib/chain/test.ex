defmodule Chain.Test do
  @moduledoc """
  Module for testing purposes only !
  Will be deleted afterwards
  """

  @base_path "/tmp/chain"

  def config(type \\ :ganache) do
    %Chain.EVM.Config{
      type: type,
      db_path: @base_path,
      output: @base_path <> "/evm.out",
      notify_pid: self(),
      clean_on_stop: true
    }
  end
end
