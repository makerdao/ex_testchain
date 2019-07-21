defmodule Chain.EVM.State do
  @moduledoc """
  Default structure for handling state into any EVM implementation

  Consist of this properties:
   - `status` - Chain status
   - `locked` - Identify if chain is locked or not
   - `task` - Task scheduled for execution after chain stop
   - `config` - default configuration for chain. Not available in implemented callback functions
   - `internal_state` - state for chain implementation

  `internal_state` - will be passed as state for all implemented callback functions
  """

  alias Chain.EVM.{Config, Notification}

  @type t :: %__MODULE__{
          status: Chain.EVM.status(),
          locked: boolean(),
          version: Version.t() | nil,
          task: Chain.EVM.scheduled_task(),
          config: Chain.EVM.Config.t(),
          internal_state: term()
        }
  @enforce_keys [:config]
  defstruct status: :none,
            locked: false,
            version: nil,
            task: nil,
            config: nil,
            internal_state: nil

  @doc """
  Set internal state
  """
  @spec internal_state(Chain.EVM.State.t(), term()) :: Chain.EVM.State.t()
  def internal_state(%__MODULE__{} = state, internal_state),
    do: %__MODULE__{state | internal_state: internal_state}

  @doc """
  Set new status to evm state.
  And if config is passed and `notify_pid` is set - notification will be sent.

  ```elixir
  %Chain.EVM.Notification{id: config.id, event: :status_changed, status}
  ```

  And if chain should not be cleaned after stop - status will be stored using `Storage.store/2`
  """
  @spec status(Chain.EVM.State.t(), Chain.EVM.status(), Chain.EVM.Config.t()) ::
          Chain.EVM.Status.t()
  def status(%__MODULE__{} = state, status, config \\ %{}) do
    Notification.send(config, Map.get(config, :id), :status_changed, status)

    unless Map.get(config, :clean_on_stop, true) do
      Storage.store(config, status)
    end

    %__MODULE__{state | status: status}
  end

  @doc """
  Set locked to true and send notification that chain was locked.
  Notification will be sent only if config is passed and `notify_pid` is set

  In case of chain is already locked - nothing will happen
  """
  @spec locked(Chain.EVM.State.t(), boolean, Chain.EVM.Config.t()) :: Chain.EVM.State.t()
  def locked(%__MODULE__{} = state, locked, config \\ %{}) do
    case locked do
      true ->
        Notification.send(config, Map.get(config, :id), :locked)

      false ->
        Notification.send(config, Map.get(config, :id), :unlocked)
    end

    %__MODULE__{state | locked: locked}
  end

  @doc """
  Set new scheduled task value
  """
  @spec task(Chain.EVM.State.t(), Chain.EVM.scheduled_task()) :: Chain.EVM.State.t()
  def task(%__MODULE__{} = state, task), do: %__MODULE__{state | task: task}

  @doc """
  Set new config into state
  """
  @spec config(Chain.EVM.State.t(), Chain.EVM.Config.t()) :: Chain.EVM.State.t()
  def config(%__MODULE__{} = state, %Config{} = config),
    do: %__MODULE__{state | config: config}
end
