defmodule BacView.BACnet.NotificationLogLimitTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.NotificationLogLimit

  setup do
    table = :ets.new(:notification_log_limit_test, [:ordered_set, :public])
    %{table: table}
  end

  test "max_entries is 1000" do
    assert NotificationLogLimit.max_entries() == 1000
  end

  test "prune keeps all entries when under the limit", %{table: table} do
    device_id = 42

    for seq <- 1..10 do
      :ets.insert(table, {{device_id, -seq, seq}, %{log_id: seq}})
    end

    NotificationLogLimit.prune(table, device_id)

    assert :ets.tab2list(table) |> length() == 10
  end

  test "prune removes oldest entries per device", %{table: table} do
    device_id = 77
    max = NotificationLogLimit.max_entries()

    for seq <- 1..(max + 5) do
      :ets.insert(table, {{device_id, -seq, seq}, %{log_id: seq}})
    end

    NotificationLogLimit.prune(table, device_id)

    remaining =
      table
      |> :ets.match_object({{device_id, :_, :_}, :_})
      |> Enum.map(fn {{_, _, seq}, _} -> seq end)
      |> Enum.sort()

    assert length(remaining) == max
    assert remaining == Enum.to_list((max + 5 - max + 1)..(max + 5))
  end

  test "prune only affects the given device", %{table: table} do
    device_a = 1
    device_b = 2
    max = NotificationLogLimit.max_entries()

    for seq <- 1..(max + 1) do
      :ets.insert(table, {{device_a, -seq, seq}, %{log_id: seq}})
      :ets.insert(table, {{device_b, -seq, seq}, %{log_id: seq}})
    end

    NotificationLogLimit.prune(table, device_a)

    assert :ets.match_object(table, {{device_a, :_, :_}, :_}) |> length() == max
    assert :ets.match_object(table, {{device_b, :_, :_}, :_}) |> length() == max + 1
  end
end
