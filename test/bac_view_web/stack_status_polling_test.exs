defmodule BacViewWeb.StackStatusPollingTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.StackStatusPolling

  test "uses fast interval while fast poll window is active" do
    now = System.monotonic_time(:millisecond)
    until = now + 5_000

    assert StackStatusPolling.poll_interval_ms(until, now) == StackStatusPolling.fast_poll_ms()
    assert StackStatusPolling.poll_interval_ms(nil, now) == StackStatusPolling.normal_poll_ms()

    assert StackStatusPolling.poll_interval_ms(until, until + 1) ==
             StackStatusPolling.normal_poll_ms()
  end

  test "ends fast poll on error, success, or timeout" do
    now = 1_000
    until = now + 10_000

    refute StackStatusPolling.end_fast_poll?(until, now, %{running?: false, last_error: nil})

    assert StackStatusPolling.end_fast_poll?(until, now, %{
             running?: false,
             last_error: :eacces
           })

    assert StackStatusPolling.end_fast_poll?(until, now, %{running?: true, last_error: nil})

    assert StackStatusPolling.end_fast_poll?(until, now + 10_000, %{
             running?: false,
             last_error: nil
           })

    assert StackStatusPolling.end_fast_poll?(nil, now, %{running?: false, last_error: :eacces})
  end

  test "stack_offline? is true only when stack failed to start" do
    refute StackStatusPolling.stack_offline?(%{running?: true, last_error: nil})
    refute StackStatusPolling.stack_offline?(%{running?: false, last_error: nil})

    assert StackStatusPolling.stack_offline?(%{running?: false, last_error: :eacces})
  end
end
