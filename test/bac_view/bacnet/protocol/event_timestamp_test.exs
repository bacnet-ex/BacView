defmodule BacView.BACnet.Protocol.EventTimestampTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    BACnetTimestamp,
    EventTimestamps
  }

  alias BacView.BACnet.Protocol.EventTimestamp

  test "formats datetime alarm timestamp for offnormal state" do
    timestamps = %EventTimestamps{
      to_offnormal: %BACnetTimestamp{
        type: :datetime,
        datetime: %BACnetDateTime{
          date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
          time: %BACnetTime{hour: 14, minute: 30, second: 0, hundredth: 0}
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

    result = EventTimestamp.alarm_since(timestamps, :offnormal)

    assert result.label =~ "27.06.2026"
    assert result.label =~ "14:30:00"
    assert is_integer(result.sort_key)
    assert result.sort_key > 0
  end

  test "returns placeholder when timestamps are missing" do
    assert EventTimestamp.alarm_since(nil, :fault) == %{at: nil, label: "-", sort_key: 0}
  end
end
