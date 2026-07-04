defmodule BacViewWeb.CovNotificationTableTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.CovNotificationTable

  test "sorted_notifications defaults to newest received first" do
    older = %{
      log_id: 1,
      received_at: ~U[2024-01-01 10:00:00Z],
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :present_value,
      formatted: "1.0",
      confirmed: false,
      time_remaining: 120
    }

    newer = %{
      log_id: 2,
      received_at: ~U[2024-01-02 10:00:00Z],
      object_id: %ObjectIdentifier{type: :binary_input, instance: 2},
      property: :present_value,
      formatted: "active",
      confirmed: true,
      time_remaining: 60
    }

    assert [^newer, ^older] = CovNotificationTable.sorted_notifications([older, newer], nil, nil)
  end

  test "sorted_notifications sorts by object id" do
    a = %{
      log_id: 1,
      received_at: ~U[2024-01-01 10:00:00Z],
      object_id: %ObjectIdentifier{type: :binary_input, instance: 2},
      property: :present_value,
      formatted: "1",
      confirmed: false,
      time_remaining: nil
    }

    b = %{
      log_id: 2,
      received_at: ~U[2024-01-02 10:00:00Z],
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :status_flags,
      formatted: "0",
      confirmed: false,
      time_remaining: nil
    }

    assert [^b, ^a] = CovNotificationTable.sorted_notifications([a, b], "object", :asc)
  end
end
