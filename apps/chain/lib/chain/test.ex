defmodule Chain.Test do
  @moduledoc """
  Module for testing purposes only !
  Will be deleted afterwards
  """

  def config(type \\ :ganache) do
    %Chain.EVM.Config{
      type: type,
      notify_pid: self(),
      clean_on_stop: true
    }
  end
end
