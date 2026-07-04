defmodule BacView.BACnet.EventRecordTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.{AlarmSummary, EventInformation}
  alias BACnet.Protocol.EventTimestamps
  alias BACnet.Protocol.EventTransitionBits
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.EventRecord

  @timestamp %BACnetTimestamp{
    type: :sequence_number,
    sequence_number: 0,
    time: nil,
    datetime: nil
  }

  test "active? detects non-normal states" do
    assert EventRecord.active?(%{event_state: :offnormal})
    assert EventRecord.active?(%{event_state: :fault})
    refute EventRecord.active?(%{event_state: :normal})
  end

  test "unacknowledged? uses acknowledged transitions" do
    ack = %EventTransitionBits{to_offnormal: false, to_fault: true, to_normal: true}

    assert EventRecord.unacknowledged?(%{
             event_state: :offnormal,
             acknowledged_transitions: ack
           })

    refute EventRecord.unacknowledged?(%{
             event_state: :normal,
             acknowledged_transitions: ack
           })
  end

  test "summary computes counts and highest priority" do
    ack = %EventTransitionBits{to_offnormal: false, to_fault: true, to_normal: true}

    events = [
      %{event_state: :offnormal, priority: 80, acknowledged_transitions: ack},
      %{event_state: :normal, priority: 10, acknowledged_transitions: ack},
      %{
        event_state: :fault,
        priority: 50,
        ack_required: true,
        acknowledged_transitions: nil
      }
    ]

    summary = EventRecord.summary(events)

    assert summary.active_count == 2
    assert summary.unacknowledged_count == 2
    assert summary.highest_priority == 50
  end

  test "from_alarm_summary builds record" do
    summary = %AlarmSummary{
      object_identifier: %ObjectIdentifier{type: :binary_input, instance: 3},
      alarm_state: :offnormal,
      acknowledged_transitions: %EventTransitionBits{
        to_offnormal: false,
        to_fault: true,
        to_normal: true
      }
    }

    record = EventRecord.from_alarm_summary(42, summary)

    assert record.device_id == 42
    assert record.event_state == :offnormal
    assert record.notify_type == :alarm
    assert record.source == :poll
    assert EventRecord.unacknowledged?(record)
  end

  test "from_event_information builds record" do
    info = %EventInformation{
      object_identifier: %ObjectIdentifier{type: :analog_input, instance: 1},
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

    record = EventRecord.from_event_information(42, info)

    assert record.device_id == 42
    assert record.event_state == :offnormal
    assert record.priority == 90
    assert record.source == :poll
  end
end
