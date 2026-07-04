defmodule BacViewWeb.SubscriptionTableTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.SubscriptionTable

  test "sorted_subscriptions sorts by object and property" do
    sub_a = %{
      device_id: 1,
      object_id: %ObjectIdentifier{type: :binary_input, instance: 2},
      property: :present_value,
      last_cov_at: nil,
      last_value_formatted: "1",
      lifetime: 3600,
      expires_at: ~U[2024-01-02 10:00:00Z]
    }

    sub_b = %{
      device_id: 1,
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :status_flags,
      last_cov_at: nil,
      last_value_formatted: "2",
      lifetime: 3600,
      expires_at: ~U[2024-01-01 10:00:00Z]
    }

    assert [^sub_b, ^sub_a] =
             SubscriptionTable.sorted_subscriptions([sub_a, sub_b], "object", :asc)

    assert [^sub_a, ^sub_b] =
             SubscriptionTable.sorted_subscriptions([sub_a, sub_b], "property", :asc)
  end
end
