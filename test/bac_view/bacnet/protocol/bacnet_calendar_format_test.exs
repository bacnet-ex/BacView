defmodule BacView.BACnet.Protocol.BacnetCalendarFormatTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    BACnetTimestamp
  }

  alias BacView.BACnet.Protocol.BacnetCalendarFormat

  test "formats specific BACnetDateTime in German layout" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
      time: %BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 13}
    }

    assert BacnetCalendarFormat.format(datetime) == "27.06.2026 17:17:43.130"
  end

  test "formats unspecified BACnetDateTime as dash" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{
        year: :unspecified,
        month: :unspecified,
        day: :unspecified,
        weekday: :unspecified
      },
      time: %BACnetTime{
        hour: :unspecified,
        minute: :unspecified,
        second: :unspecified,
        hundredth: :unspecified
      }
    }

    assert BacnetCalendarFormat.format(datetime) == "—"
  end

  test "formats BACnetDate and BACnetTime separately" do
    date = %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6}
    time = %BACnetTime{hour: 8, minute: 5, second: 0, hundredth: 0}

    assert BacnetCalendarFormat.format(date) == "27.06.2026"
    assert BacnetCalendarFormat.format(time) == "08:05:00.000"
  end

  test "formats BACnetTimestamp variants" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
      time: %BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 0}
    }

    assert BacnetCalendarFormat.format(%BACnetTimestamp{
             type: :datetime,
             datetime: datetime,
             time: nil,
             sequence_number: nil
           }) == "27.06.2026 17:17:43.000"

    assert BacnetCalendarFormat.format(%BACnetTimestamp{
             type: :time,
             time: %BACnetTime{hour: 9, minute: 30, second: 0, hundredth: 0},
             datetime: nil,
             sequence_number: nil
           }) == "09:30:00.000"

    assert BacnetCalendarFormat.format(%BACnetTimestamp{
             type: :sequence_number,
             sequence_number: 42,
             datetime: nil,
             time: nil
           }) == "#42"
  end
end
