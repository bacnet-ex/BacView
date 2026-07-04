defmodule BacView.BACnet.NotificationLogLimit do
  @moduledoc false

  @max_entries 1000

  @spec max_entries() :: pos_integer()
  def max_entries(), do: @max_entries

  @spec prune(:ets.tid() | atom(), integer()) :: :ok
  def prune(table, device_id) when is_integer(device_id) do
    entries = :ets.match_object(table, {{device_id, :_, :_}, :_})
    drop = length(entries) - @max_entries

    if drop > 0 do
      entries
      |> Enum.sort_by(fn {{_table, neg_micro, seq}, _device_id} -> {neg_micro, seq} end, :desc)
      |> Enum.take(drop)
      |> Enum.each(&:ets.delete_object(table, &1))
    end

    :ok
  end
end
