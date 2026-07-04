defmodule BacView.BACnet.ActiveAlarmsTest do
  use ExUnit.Case, async: true

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

  setup do
    reset_tables!()
    on_exit(fn -> reset_tables!() end)
    :ok
  end

  test "uses event_timestamps from object cache without properties table" do
    device_id = 42
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
    assert entry.object_path == "/devices/42/objects/analog_input/5"
  end

  defp reset_tables! do
    for table <- [:bacview_events, :bacview_objects, :bacview_properties] do
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end

    :ets.new(:bacview_events, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(:bacview_objects, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(:bacview_properties, [:named_table, :set, :public, read_concurrency: true])
  end
end
