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

  test "max_cov_subscription_entries is 1000" do
    assert NotificationLogLimit.max_cov_subscription_entries() == 1000
  end

  test "max_cov_device_entries is 50000" do
    assert NotificationLogLimit.max_cov_device_entries() == 50_000
  end

  describe "prune_device/2" do
    test "keeps all entries when under the limit", %{table: table} do
      device_id = 42

      for seq <- 1..10 do
        :ets.insert(table, {{device_id, -seq, seq}, %{log_id: seq}})
      end

      NotificationLogLimit.prune_device(table, device_id)

      assert :ets.tab2list(table) |> length() == 10
    end

    test "removes oldest entries per device", %{table: table} do
      device_id = 77
      max = NotificationLogLimit.max_entries()

      for seq <- 1..(max + 5) do
        :ets.insert(table, {{device_id, -seq, seq}, %{log_id: seq}})
      end

      NotificationLogLimit.prune_device(table, device_id)

      remaining =
        table
        |> :ets.match_object({{device_id, :_, :_}, :_})
        |> Enum.map(fn {{_, _, seq}, _} -> seq end)
        |> Enum.sort()

      assert length(remaining) == max
      assert remaining == Enum.to_list((max + 5 - max + 1)..(max + 5))
    end

    test "only affects the given device", %{table: table} do
      device_a = 1
      device_b = 2
      max = NotificationLogLimit.max_entries()

      for seq <- 1..(max + 1) do
        :ets.insert(table, {{device_a, -seq, seq}, %{log_id: seq}})
        :ets.insert(table, {{device_b, -seq, seq}, %{log_id: seq}})
      end

      NotificationLogLimit.prune_device(table, device_a)

      assert :ets.match_object(table, {{device_a, :_, :_}, :_}) |> length() == max
      assert :ets.match_object(table, {{device_b, :_, :_}, :_}) |> length() == max + 1
    end
  end

  describe "prune_cov_subscription/2" do
    test "removes oldest entries per subscription", %{table: table} do
      device_id = 10
      sub_a = {device_id, :analog_input, 1, :present_value}
      sub_b = {device_id, :analog_input, 2, :present_value}
      max = NotificationLogLimit.max_cov_subscription_entries()

      for seq <- 1..(max + 3) do
        {device_id, type_a, instance_a, property_a} = sub_a
        {^device_id, type_b, instance_b, property_b} = sub_b

        :ets.insert(
          table,
          {{device_id, type_a, instance_a, property_a, -seq, seq}, %{log_id: seq, sub: :a}}
        )

        :ets.insert(
          table,
          {{device_id, type_b, instance_b, property_b, -seq, seq}, %{log_id: seq, sub: :b}}
        )
      end

      NotificationLogLimit.prune_cov_subscription(table, sub_a)

      remaining_a =
        table
        |> :ets.match_object({{device_id, :analog_input, 1, :present_value, :_, :_}, :_})
        |> Enum.map(fn {{_, _, _, _, _, seq}, _} -> seq end)
        |> Enum.sort()

      remaining_b =
        table
        |> :ets.match_object({{device_id, :analog_input, 2, :present_value, :_, :_}, :_})
        |> length()

      assert length(remaining_a) == max
      assert remaining_a == Enum.to_list((max + 3 - max + 1)..(max + 3))
      assert remaining_b == max + 3
    end
  end

  describe "prune_cov_device/2" do
    test "removes oldest entries across subscriptions when over device limit", %{table: table} do
      device_id = 20
      max = NotificationLogLimit.max_cov_device_entries()

      for seq <- 1..(max + 7) do
        :ets.insert(
          table,
          {{device_id, :binary_input, rem(seq, 5), :present_value, -seq, seq}, %{log_id: seq}}
        )
      end

      NotificationLogLimit.prune_cov_device(table, device_id)

      remaining =
        table
        |> :ets.match_object({{device_id, :_, :_, :_, :_, :_}, :_})
        |> Enum.map(fn {{_, _, _, _, _, seq}, _} -> seq end)
        |> Enum.sort()

      assert length(remaining) == max
      assert remaining == Enum.to_list((max + 7 - max + 1)..(max + 7))
    end

    test "only affects the given device", %{table: table} do
      device_a = 30
      device_b = 31
      max = NotificationLogLimit.max_cov_device_entries()

      for seq <- 1..(max + 2) do
        :ets.insert(
          table,
          {{device_a, :analog_input, 1, :present_value, -seq, seq}, %{log_id: seq}}
        )

        :ets.insert(
          table,
          {{device_b, :analog_input, 1, :present_value, -seq, seq}, %{log_id: seq}}
        )
      end

      NotificationLogLimit.prune_cov_device(table, device_a)

      assert :ets.match_object(table, {{device_a, :_, :_, :_, :_, :_}, :_}) |> length() == max
      assert :ets.match_object(table, {{device_b, :_, :_, :_, :_, :_}, :_}) |> length() == max + 2
    end
  end
end
