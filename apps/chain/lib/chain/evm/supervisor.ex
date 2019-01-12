defmodule Chain.EVM.Supervisor do
  @moduledoc """
  Supervisor that will watch all chains running
  """

  # Automatically defines child_spec/1
  use DynamicSupervisor

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start new **supervised** EVM process
  """
  @spec start_evm(module(), Chain.EVM.Config.t()) :: DynamicSupervisor.on_start_child()
  def start_evm(module, %Chain.EVM.Config{} = config),
    do: DynamicSupervisor.start_child(__MODULE__, {module, config})
end
