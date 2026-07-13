defmodule BacView.BACnet.AlarmEventTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.EventInformation
  alias BACnet.Protocol.EventTimestamps
  alias BACnet.Protocol.EventTransitionBits
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.UnconfirmedEventNotification
  alias BacView.BACnet.{AlarmEvent, EventRecord}
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_events, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_notification_log, [:named_table, :ordered_set, :public, read_concurrency: true]},
    {:bacview_notification_seq, [:named_table, :set, :public]}
  ]

  @timestamp %BACnetTimestamp{
    type: :sequence_number,
    sequence_number: 0,
    time: nil,
    datetime: nil
  }

  defp sample_notification(overrides) do
    defaults = %{
      process_identifier: 1,
      initiating_device: %ObjectIdentifier{type: :device, instance: 1},
      event_object: %ObjectIdentifier{type: :analog_input, instance: 1},
      timestamp: @timestamp,
      notification_class: 1,
      priority: 80,
      event_type: :change_of_state,
      message_text: "Test",
      notify_type: :alarm,
      ack_required: false,
      from_state: :normal,
      to_state: :offnormal,
      event_values: nil
    }

    struct(UnconfirmedEventNotification, Map.merge(defaults, Map.new(overrides)))
  end

  test "list_polled_events returns only polled records" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 99
      object_id = %ObjectIdentifier{type: :analog_input, instance: 1}

      info = %EventInformation{
        object_identifier: object_id,
        event_state: :offnormal,
        acknowledged_transitions: %EventTransitionBits{
          to_offnormal: false,
          to_fault: true,
          to_normal: true
        },
        event_timestamps: %EventTimestamps{
          to_offnormal: @timestamp,
          to_fault: @timestamp,
          to_normal: @timestamp
        },
        notify_type: :alarm,
        event_enable: %EventTransitionBits{
          to_offnormal: true,
          to_fault: true,
          to_normal: true
        },
        event_priorities: {90, 70, 50}
      }

      polled = EventRecord.from_event_information(device_id, info)

      notification =
        EventRecord.from_notification(
          device_id,
          sample_notification(
            event_object: object_id,
            to_state: :fault,
            from_state: :normal,
            message_text: "Fault"
          )
        )

      :ets.insert(:bacview_events, {EventRecord.key(device_id, object_id), polled})

      received_at = DateTime.utc_now()

      :ets.insert(
        :bacview_notification_log,
        {{device_id, -1, 1}, Map.put(notification, :received_at, received_at)}
      )

      events = AlarmEvent.list_polled_events(device_id)
      assert length(events) == 1
      assert hd(events).source == :poll

      notifications = AlarmEvent.list_notifications(device_id)
      assert length(notifications) == 1
      assert hd(notifications).source == :notification
    end)
  end

  test "list_notifications returns newest first" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 77
      object_id = %ObjectIdentifier{type: :binary_input, instance: 2}

      older =
        EventRecord.from_notification(
          device_id,
          sample_notification(
            event_object: object_id,
            to_state: :normal,
            from_state: :offnormal,
            priority: 50,
            message_text: "Older"
          )
        )
        |> Map.put(:log_id, 1)
        |> Map.put(:received_at, ~U[2026-01-01 10:00:00Z])

      newer =
        EventRecord.from_notification(
          device_id,
          sample_notification(
            event_object: object_id,
            to_state: :offnormal,
            from_state: :normal,
            priority: 40,
            message_text: "Newer"
          )
        )
        |> Map.put(:log_id, 2)
        |> Map.put(:received_at, ~U[2026-01-02 10:00:00Z])

      :ets.insert(
        :bacview_notification_log,
        {{device_id, -DateTime.to_unix(older.received_at, :microsecond), 1}, older}
      )

      :ets.insert(
        :bacview_notification_log,
        {{device_id, -DateTime.to_unix(newer.received_at, :microsecond), 2}, newer}
      )

      [first, second] = AlarmEvent.list_notifications(device_id)
      assert first.message_text == "Newer"
      assert second.message_text == "Older"
    end)
  end

  test "export returns error when device is not known" do
    assert AlarmEvent.export(99_999, :csv) == {:error, :device_not_found}
  end
end
