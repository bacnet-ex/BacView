defmodule BacView.BACnet.Protocol.TrendLogChartTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    DeviceObjectPropertyRef,
    ObjectIdentifier
  }

  alias BacView.BACnet.Protocol.{TrendLogChart, TrendLogReader}
  alias BacView.Timezone

  defp datetime(year, month, day, hour, minute, second) do
    %BACnetDateTime{
      date: %BACnetDate{year: year, month: month, day: day, weekday: 6},
      time: %BACnetTime{hour: hour, minute: minute, second: second, hundredth: 0}
    }
  end

  test "build creates single series for trend log" do
    records = [
      %{
        type: :log_record,
        timestamp: datetime(2025, 3, 15, 10, 30, 0),
        datum: 21.5,
        status_flags: nil
      }
    ]

    object_id = %ObjectIdentifier{type: :trend_log, instance: 1}

    data =
      TrendLogChart.build(records, object_id,
        property_refs: [],
        object_units: :degrees_celsius,
        start_dt: ~N[2025-03-15 10:00:00],
        end_dt: ~N[2025-03-15 11:00:00]
      )

    assert [series] = data.series
    assert series.scale_id == "degrees_celsius"
    assert [%{v: 21.5}] = series.points
    assert [%{id: "degrees_celsius", side: "left"}] = data.scales
  end

  test "build includes referenced object description in series label" do
    ref = %DeviceObjectPropertyRef{
      device_identifier: nil,
      object_identifier: %ObjectIdentifier{type: :analog_input, instance: 1},
      property_identifier: :present_value,
      property_array_index: nil
    }

    records = [
      %{
        type: :log_record,
        timestamp: datetime(2025, 3, 15, 10, 30, 0),
        datum: 21.5,
        status_flags: nil
      }
    ]

    object_id = %ObjectIdentifier{type: :trend_log, instance: 1}

    data =
      TrendLogChart.build(records, object_id,
        property_refs: [ref],
        device_objects: [
          %{
            type: :analog_input,
            instance: 1,
            units: :degrees_celsius,
            description: "Raumtemperatur EG"
          }
        ],
        start_dt: ~N[2025-03-15 10:00:00],
        end_dt: ~N[2025-03-15 11:00:00]
      )

    assert [series] = data.series
    assert series.label == "Raumtemperatur EG (analog_input:1 present value)"
  end

  test "build groups multiple series by engineering unit" do
    ref_ai = %DeviceObjectPropertyRef{
      device_identifier: nil,
      object_identifier: %ObjectIdentifier{type: :analog_input, instance: 1},
      property_identifier: :present_value,
      property_array_index: nil
    }

    ref_bo = %DeviceObjectPropertyRef{
      device_identifier: nil,
      object_identifier: %ObjectIdentifier{type: :binary_input, instance: 2},
      property_identifier: :present_value,
      property_array_index: nil
    }

    records = [
      %{
        type: :log_multiple_record,
        timestamp: datetime(2025, 3, 15, 10, 30, 0),
        data: [12.0, true]
      }
    ]

    object_id = %ObjectIdentifier{type: :trend_log_multiple, instance: 2}

    data =
      TrendLogChart.build(records, object_id,
        property_refs: [ref_ai, ref_bo],
        device_objects: [
          %{type: :analog_input, instance: 1, units: :degrees_celsius},
          %{type: :binary_input, instance: 2, units: nil}
        ],
        start_dt: ~N[2025-03-15 10:00:00],
        end_dt: ~N[2025-03-15 11:00:00]
      )

    assert length(data.series) == 2
    assert Enum.any?(data.series, &(&1.scale_id == "degrees_celsius"))
    assert Enum.any?(data.series, &(&1.scale_id == "raw"))
  end

  test "range_from_records uses earliest and latest timestamps" do
    records = [
      %{timestamp: datetime(2025, 3, 15, 12, 0, 0)},
      %{timestamp: datetime(2025, 3, 15, 10, 0, 0)},
      %{timestamp: datetime(2025, 3, 15, 11, 30, 0)}
    ]

    {start_dt, end_dt} = TrendLogChart.range_from_records(records)

    assert start_dt == ~N[2025-03-15 10:00:00]
    assert end_dt == ~N[2025-03-15 12:00:00]
  end

  test "to_form_value and parse_form_value round-trip naive wall clock" do
    naive = ~N[2025-03-15 18:28:00]

    assert TrendLogChart.to_form_value(naive) == "2025-03-15T18:28"
    assert {:ok, ^naive} = TrendLogChart.parse_form_value("2025-03-15T18:28")
  end

  test "build anchors BACnet wall clock timestamps to configured timezone chart epochs" do
    records = [
      %{
        type: :log_record,
        timestamp: datetime(2025, 3, 15, 18, 28, 0),
        datum: 21.5,
        status_flags: nil
      }
    ]

    object_id = %ObjectIdentifier{type: :trend_log, instance: 1}

    data =
      TrendLogChart.build(records, object_id,
        property_refs: [],
        object_units: :degrees_celsius,
        start_dt: ~N[2025-03-15 18:00:00],
        end_dt: ~N[2025-03-15 19:00:00]
      )

    expected_ms = Timezone.naive_to_unix_ms(~N[2025-03-15 18:28:00])

    assert [%{t: ^expected_ms, v: 21.5}] = hd(data.series).points
  end

  test "filter_records keeps only records inside range" do
    inside = %{
      timestamp: datetime(2025, 3, 15, 10, 30, 0)
    }

    outside = %{
      timestamp: datetime(2025, 3, 15, 12, 30, 0)
    }

    filtered =
      TrendLogReader.filter_records(
        [inside, outside],
        ~N[2025-03-15 10:00:00],
        ~N[2025-03-15 11:00:00]
      )

    assert filtered == [inside]
  end
end
