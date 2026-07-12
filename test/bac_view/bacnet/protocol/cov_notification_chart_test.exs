defmodule BacView.BACnet.Protocol.CovNotificationChartTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Protocol.CovNotificationChart

  test "trendable_property? accepts boolean and numeric types" do
    assert CovNotificationChart.trendable_property?(%{type: "BOOLEAN", value: true})
    assert CovNotificationChart.trendable_property?(%{type: "REAL", value: 12.5})
    assert CovNotificationChart.trendable_property?(%{bac_type: :unsigned_integer, value: nil})
    refute CovNotificationChart.trendable_property?(%{type: "CHARACTER STRING", value: "x"})
  end

  test "build creates chart points from matching notifications" do
    object_id = %ObjectIdentifier{type: :analog_input, instance: 1}
    subscription = %{object_id: object_id, property: :present_value}

    notifications = [
      %{
        object_id: object_id,
        property: :present_value,
        value: 21.5,
        received_at: ~U[2025-03-15 10:30:00Z]
      },
      %{
        object_id: object_id,
        property: :present_value,
        value: 22.0,
        received_at: ~U[2025-03-15 10:31:00Z]
      },
      %{
        object_id: object_id,
        property: :status_flags,
        value: 1,
        received_at: ~U[2025-03-15 10:32:00Z]
      }
    ]

    data = CovNotificationChart.build(notifications, subscription)

    assert [series] = data.series
    assert length(series.points) == 2
    assert Enum.all?(series.points, &is_map/1)
    assert series.label == "analog_input:1 present value"
  end

  test "build includes object description in series label" do
    object_id = %ObjectIdentifier{type: :analog_input, instance: 1}
    subscription = %{object_id: object_id, property: :present_value}

    notifications = [
      %{
        object_id: object_id,
        property: :present_value,
        value: 21.5,
        received_at: ~U[2025-03-15 10:30:00Z]
      }
    ]

    data =
      CovNotificationChart.build(notifications, subscription,
        object: %{
          type: :analog_input,
          instance: 1,
          description: "Raumtemperatur EG"
        }
      )

    assert [series] = data.series
    assert series.label == "Raumtemperatur EG (analog_input:1 present value)"
  end

  test "filter_notifications_by_range keeps notifications in selected window" do
    object_id = %ObjectIdentifier{type: :binary_input, instance: 2}

    notifications = [
      %{object_id: object_id, property: :present_value, received_at: ~U[2025-03-15 08:00:00Z]},
      %{object_id: object_id, property: :present_value, received_at: ~U[2025-03-15 09:30:00Z]},
      %{object_id: object_id, property: :present_value, received_at: ~U[2025-03-15 11:00:00Z]}
    ]

    filtered =
      CovNotificationChart.filter_notifications_by_range(
        notifications,
        ~N[2025-03-15 10:00:00],
        ~N[2025-03-15 11:00:00]
      )

    assert length(filtered) == 1
    assert hd(filtered).received_at == ~U[2025-03-15 09:30:00Z]
  end
end
