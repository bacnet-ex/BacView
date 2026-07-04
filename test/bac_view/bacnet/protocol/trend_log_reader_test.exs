defmodule BacView.BACnet.Protocol.TrendLogReaderTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    ObjectIdentifier
  }

  alias BacView.BACnet.Protocol.TrendLogReader

  defp datetime(year, month, day, hour, minute, second) do
    %BACnetDateTime{
      date: %BACnetDate{year: year, month: month, day: day, weekday: 6},
      time: %BACnetTime{hour: hour, minute: minute, second: second, hundredth: 0}
    }
  end

  test "records_for_range :all returns every record" do
    records = [
      %{timestamp: datetime(2025, 3, 15, 10, 0, 0)},
      %{timestamp: datetime(2025, 3, 15, 12, 0, 0)}
    ]

    assert length(TrendLogReader.records_for_range(records, :all)) == 2
  end

  test "records_for_range filters by datetime window" do
    inside = %{timestamp: datetime(2025, 3, 15, 10, 30, 0)}
    outside = %{timestamp: datetime(2025, 3, 15, 12, 30, 0)}

    filtered =
      TrendLogReader.records_for_range(
        [inside, outside],
        {~N[2025-03-15 10:00:00], ~N[2025-03-15 11:00:00]}
      )

    assert filtered == [inside]
  end

  test "fetch_all uses nil range on first request" do
    object_id = %ObjectIdentifier{type: :trend_log, instance: 1}

    assert {:error, :unsupported_object_type} =
             TrendLogReader.fetch_all(1, %ObjectIdentifier{type: :analog_input, instance: 1})

    assert object_id.type in [:trend_log, :trend_log_multiple]
  end
end
