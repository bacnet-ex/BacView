defmodule BacView.BACnet.Protocol.CovNotificationExportTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PriorityArray
  alias BacView.BACnet.Protocol.CovNotificationExport
  alias BacView.Timezone

  test "exports selected notifications with a full priority array" do
    output = %ObjectIdentifier{type: :analog_output, instance: 3}
    other = %ObjectIdentifier{type: :analog_input, instance: 1}
    array = %PriorityArray{priority_1: 99, priority_8: 21.5}
    earlier = ~U[2026-03-15 09:30:00Z]
    later = ~U[2026-03-15 10:30:00Z]

    notifications = [
      notification(output, :priority_array, array, "21.5 (P8)", later, 2),
      notification(output, :present_value, 21.5, "21.5 °C", earlier, 1),
      notification(output, :present_value, 22.0, "22.0 °C", later, 4),
      notification(other, :present_value, 1.0, "1.0", later, 3)
    ]

    keys =
      MapSet.new([
        {:analog_output, 3, :priority_array},
        {:analog_output, 3, :present_value}
      ])

    rows = CovNotificationExport.select(notifications, keys)

    assert Enum.map(rows, & &1.log_id) == [1, 2, 4]

    csv =
      CovNotificationExport.to_csv(rows,
        objects: [
          %{
            type: :analog_output,
            instance: 3,
            description: "Zuluftklappe",
            units: :degrees_celsius
          }
        ]
      )

    [header, first_row, second_row | _rest] = String.split(csv, "\n")
    earlier_ts = chart_timestamp(earlier)
    later_ts = chart_timestamp(later)

    assert header ==
             "timestamp;\"Zuluftklappe (analog_output:3 present value) (°C)\";timestamp;\"Zuluftklappe (analog_output:3 priority array)\""

    assert first_row ==
             "#{earlier_ts};21.500000;#{later_ts};\"[1: 99, 2: NULL, 3: NULL, 4: NULL, 5: NULL, 6: NULL, 7: NULL, 8: 21.5, 9: NULL, 10: NULL, 11: NULL, 12: NULL, 13: NULL, 14: NULL, 15: NULL, 16: NULL]\""

    assert second_row == "#{later_ts};22.000000;;"
    refute csv =~ "analog_input"
    refute csv =~ "21.5 °C"

    objects = [%{type: :analog_output, instance: 3, name: "  "}]

    json =
      rows
      |> CovNotificationExport.to_json(device_id: 42, objects: objects)
      |> Jason.decode!()

    assert json["device_id"] == 42

    present_value =
      Enum.find(json["notifications"], fn entry -> entry["property"] == "present_value" end)

    priority_array =
      Enum.find(json["notifications"], fn entry -> entry["property"] == "priority_array" end)

    assert present_value["value"] == 21.5
    assert present_value["value_text"] == "21.5 °C"
    assert present_value["object_name"] == nil
    assert length(priority_array["value"]) == 16
    assert Enum.at(priority_array["value"], 0) == %{"priority" => 1, "value" => 99}
    assert Enum.at(priority_array["value"], 7) == %{"priority" => 8, "value" => 21.5}
    assert Enum.at(priority_array["value"], 1) == %{"priority" => 2, "value" => nil}
    assert priority_array["value_text"] =~ "8: 21.5"
  end

  test "matches a numeric property selected as text and names one subscription" do
    object_id = %ObjectIdentifier{type: :analog_value, instance: 4}

    rows =
      CovNotificationExport.select(
        [notification(object_id, 85, [1, nil], nil, ~U[2026-03-15 10:00:00Z], 1)],
        MapSet.new([{:analog_value, 4, "85"}])
      )

    assert length(rows) == 1
    csv = CovNotificationExport.to_csv(rows)
    assert csv =~ "timestamp;\"analog_value:4 85\"\n"
    assert csv =~ "\"[1, -]\""

    assert CovNotificationExport.filename(7, MapSet.new([{:analog_value, 4, "85"}]), "json") ==
             "bacview-cov-analog_value-4-85.json"

    assert CovNotificationExport.filename(
             7,
             MapSet.new([{:analog_value, 4, :present_value}, {:analog_value, 5, :present_value}]),
             "csv"
           ) == "bacview-cov-7-notifications.csv"
  end

  defp chart_timestamp(%DateTime{} = received_at) do
    received_at
    |> DateTime.to_unix(:millisecond)
    |> Timezone.unix_ms_to_naive()
    |> NaiveDateTime.to_string()
  end

  defp notification(object_id, property, value, formatted, received_at, log_id) do
    %{
      device_id: 42,
      object_id: object_id,
      property: property,
      value: value,
      formatted: formatted,
      confirmed: false,
      time_remaining: 3000,
      received_at: received_at,
      log_id: log_id
    }
  end
end
