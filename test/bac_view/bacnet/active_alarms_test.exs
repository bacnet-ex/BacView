defmodule BacView.BACnet.ActiveAlarmsTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.{
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    BACnetTimestamp,
    EventTimestamps,
    EventTransitionBits,
    ObjectIdentifier,
    StatusFlags
  }

  alias BacView.BACnet.{ActiveAlarms, EventRecord}
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_events, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_notification_log, [:named_table, :ordered_set, :public, read_concurrency: true]},
    {:bacview_objects, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_properties, [:named_table, :set, :public, read_concurrency: true]}
  ]

  test "uses event_timestamps from object cache without properties table" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 90_041
      object_id = %ObjectIdentifier{type: :analog_input, instance: 5}
      updated_at = ~U[2026-06-27 10:00:00Z]

      timestamps = %EventTimestamps{
        to_offnormal: %BACnetTimestamp{
          type: :datetime,
          datetime: %BACnetDateTime{
            date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
            time: %BACnetTime{hour: 9, minute: 15, second: 0, hundredth: 0}
          },
          time: nil,
          sequence_number: nil
        },
        to_fault: %BACnetTimestamp{
          type: :sequence_number,
          sequence_number: 0,
          time: nil,
          datetime: nil
        },
        to_normal: %BACnetTimestamp{
          type: :sequence_number,
          sequence_number: 0,
          time: nil,
          datetime: nil
        }
      }

      event =
        EventRecord.from_alarm_summary(device_id, %BACnet.Protocol.AlarmSummary{
          object_identifier: object_id,
          alarm_state: :offnormal,
          acknowledged_transitions: %EventTransitionBits{
            to_offnormal: false,
            to_fault: true,
            to_normal: true
          }
        })
        |> Map.put(:updated_at, updated_at)

      :ets.insert(:bacview_events, {EventRecord.key(device_id, object_id), event})

      :ets.insert(:bacview_objects, {
        device_id,
        [
          %{
            type: :analog_input,
            instance: 5,
            description: "Supply air temp",
            status_flags: %StatusFlags{
              in_alarm: true,
              fault: false,
              overridden: false,
              out_of_service: false
            },
            event_timestamps: timestamps
          }
        ]
      })

      [entry] = ActiveAlarms.list(device_id: device_id)

      assert entry.description == "Supply air temp"
      assert entry.alarm_since_label =~ "27.06.2026"
      assert entry.alarm_since_label =~ "09:15:00"
      assert entry.object_path == "/devices/90041/objects/analog_input/5"
    end)
  end

  test "object_alarm_since uses event_timestamps from object cache" do
    timestamps = %EventTimestamps{
      to_offnormal: %BACnetTimestamp{
        type: :datetime,
        datetime: %BACnetDateTime{
          date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
          time: %BACnetTime{hour: 9, minute: 15, second: 0, hundredth: 0}
        },
        time: nil,
        sequence_number: nil
      },
      to_fault: %BACnetTimestamp{
        type: :sequence_number,
        sequence_number: 0,
        time: nil,
        datetime: nil
      },
      to_normal: %BACnetTimestamp{
        type: :sequence_number,
        sequence_number: 0,
        time: nil,
        datetime: nil
      }
    }

    obj = %{
      type: :analog_input,
      instance: 5,
      event_state: :offnormal,
      event_timestamps: timestamps,
      status_flags: %StatusFlags{
        in_alarm: true,
        fault: false,
        overridden: false,
        out_of_service: false
      }
    }

    since = ActiveAlarms.object_alarm_since(obj)

    assert since.label =~ "27.06.2026"
    assert since.label =~ "09:15:00"
    assert since.sort_key > 0
  end

  test "object_alarm_since falls back to updated_at when timestamps are unknown" do
    updated_at = ~U[2026-06-27 10:00:00Z]

    obj = %{
      type: :binary_input,
      instance: 1,
      updated_at: updated_at,
      status_flags: %StatusFlags{
        in_alarm: true,
        fault: false,
        overridden: false,
        out_of_service: false
      }
    }

    since = ActiveAlarms.object_alarm_since(obj)

    assert since.label == "—"
    assert since.sort_key == DateTime.to_unix(updated_at, :microsecond)
  end

  test "device_groups returns per-device alarm counts including status flags" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 90_043
      object_id = %ObjectIdentifier{type: :binary_input, instance: 3}

      :ets.insert(:bacview_objects, {
        device_id,
        [
          %{
            type: :binary_input,
            instance: 3,
            description: "Door contact",
            status_flags: %StatusFlags{
              in_alarm: true,
              fault: false,
              overridden: false,
              out_of_service: false
            },
            updated_at: ~U[2026-06-27 10:00:00Z]
          }
        ]
      })

      assert [%{device_id: ^device_id, count: 1}] = ActiveAlarms.device_groups([90_043, 90_099])

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

      assert [%{device_id: ^device_id, count: 1}] = ActiveAlarms.device_groups([90_043, 90_099])
    end)
  end

  test "includes active NC notification events in popup entries" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 90_044
      object_id = %ObjectIdentifier{type: :analog_value, instance: 7}

      notification =
        EventRecord.from_notification(
          device_id,
          %BACnet.Protocol.Services.UnconfirmedEventNotification{
            process_identifier: 1,
            initiating_device: %ObjectIdentifier{type: :device, instance: device_id},
            event_object: object_id,
            timestamp: %BACnetTimestamp{
              type: :sequence_number,
              sequence_number: 0,
              time: nil,
              datetime: nil
            },
            notification_class: 2,
            priority: 60,
            event_type: :change_of_value,
            message_text: "High limit exceeded",
            notify_type: :alarm,
            ack_required: false,
            from_state: :normal,
            to_state: :high_limit,
            event_values: nil
          }
        )
        |> Map.put(:log_id, 1)
        |> Map.put(:received_at, ~U[2026-01-02 12:00:00Z])
        |> Map.put(:updated_at, ~U[2026-01-02 12:00:00Z])

      :ets.insert(
        :bacview_notification_log,
        {{device_id, -DateTime.to_unix(notification.received_at, :microsecond), 1}, notification}
      )

      [entry] = ActiveAlarms.list(device_id: device_id)

      assert entry.object_label == "analog_value:7"
      assert entry.description == "High limit exceeded"
    end)
  end
end
