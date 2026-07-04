defmodule BacViewWeb.StackStatusPolling do
  @moduledoc false

  @fast_poll_ms 500
  @normal_poll_ms 5_000
  @fast_poll_max_ms 10_000

  @spec fast_poll_ms() :: pos_integer()
  def fast_poll_ms(), do: @fast_poll_ms

  @spec normal_poll_ms() :: pos_integer()
  def normal_poll_ms(), do: @normal_poll_ms

  @spec begin_fast_poll() :: integer()
  def begin_fast_poll(), do: System.monotonic_time(:millisecond) + @fast_poll_max_ms

  @spec poll_interval_ms(integer() | nil, integer()) :: pos_integer()
  def poll_interval_ms(fast_poll_until, now \\ System.monotonic_time(:millisecond))

  def poll_interval_ms(nil, _now), do: @normal_poll_ms
  def poll_interval_ms(until, now) when is_integer(until) and until > now, do: @fast_poll_ms
  def poll_interval_ms(_until, _now), do: @normal_poll_ms

  @spec end_fast_poll?(integer() | nil, integer(), map()) :: boolean()
  def end_fast_poll?(fast_poll_until, now, status)
      when is_integer(fast_poll_until) and is_integer(now) and is_map(status) do
    stack_offline_due_to_error?(status) or Map.get(status, :running?, false) or
      now >= fast_poll_until
  end

  def end_fast_poll?(nil, _now, _status), do: true

  defp stack_offline_due_to_error?(%{running?: false, last_error: error})
       when not is_nil(error),
       do: true

  defp stack_offline_due_to_error?(_stack_offline_due_to_error), do: false
end
