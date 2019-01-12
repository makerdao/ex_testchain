defmodule Chain.Test.ChainHelper do
  @doc """
  Receive loop for events.

  Mainly this function is made for testing receiving notifications
  from chain.

  For example in test you could spawn a new pid and set it 
  as notifications receiver.
  After that you could use `:erlang.trace/3` for handling messages 
  from newly created pid.

  Example: 
  ```elixir
    pid = spawn(&Chain.Test.ChainHelper.receive_loop/0)
    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, msg}
    # Unbind tracing if needed
    :erlang.trace(pid, false, [:receive])
  ```
  """
  @spec receive_loop() :: :ok
  def receive_loop() do
    receive do
      _ ->
        receive_loop()
    end
  end

  @doc """
  Alias for `:erlang.trace/3` with default params
  """
  @spec trace(pid) :: integer
  def trace(pid), do: :erlang.trace(pid, true, [:receive])

  @doc """
  Alias for `:erlang.trace/3` with default params (false as 2nd param)
  """
  @spec trace(pid) :: integer
  def untrace(pid), do: :erlang.trace(pid, false, [:receive])
end
