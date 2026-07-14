defmodule BacViewWeb.DeviceBadgeCountsTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.EventRecord
  alias BacView.BACnet.Subscription
  alias BacViewWeb.DeviceBadgeCounts
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_events, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_subscriptions, [:named_table, :set, :public, read_concurrency: true]}
  ]

  test "build returns sparse per-device alarm and cov counts" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 90_042
      object_id = %ObjectIdentifier{type: :analog_input, instance: 1}

      event =
        EventRecord.from_alarm_summary(device_id, %BACnet.Protocol.AlarmSummary{
          object_identifier: object_id,
          alarm_state: :offnormal,
          acknowledged_transitions: %BACnet.Protocol.EventTransitionBits{
            to_offnormal: false,
            to_fault: true,
            to_normal: true
          }
        })

      :ets.insert(:bacview_events, {EventRecord.key(device_id, object_id), event})

      sub =
        Subscription.build(device_id, {127, 0, 0, 1, 47_808}, object_id, :present_value,
          process_id: 1,
          lifetime: 60
        )

      :ets.insert(
        :bacview_subscriptions,
        {Subscription.key(device_id, object_id, :present_value), sub}
      )

      counts = DeviceBadgeCounts.build([90_042, 90_099])

      assert counts.alarms == %{90_042 => 1}
      assert counts.cov == %{90_042 => 1}
      assert DeviceBadgeCounts.alarm_count(counts, 90_042) == 1
      assert DeviceBadgeCounts.cov_count(counts, 90_042) == 1
      assert DeviceBadgeCounts.alarm_count(counts, 99) == 0
      assert DeviceBadgeCounts.cov_count(counts, 99) == 0
      assert DeviceBadgeCounts.total_alarm_count(counts) == 1
      assert DeviceBadgeCounts.total_cov_count(counts) == 1

      devices = [%{id: 90_042, name: "AHU-1", instance: 1, description: "Main air handler"}]

      assert [
               %{
                 device_id: 90_042,
                 device_label: "AHU-1",
                 device_description: "Main air handler",
                 count: 1,
                 device_path: "/devices/90042?tab=subscriptions"
               }
             ] = DeviceBadgeCounts.cov_device_groups(devices, counts)
    end)
  end
end
