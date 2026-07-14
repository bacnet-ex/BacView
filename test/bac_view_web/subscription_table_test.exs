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

  test "enrich_subscriptions attaches object names and descriptions" do
    sub = %{
      device_id: 1,
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :present_value
    }

    objects = [
      %{
        type: :analog_input,
        instance: 1,
        name: "AI-1",
        description: "Raumtemperatur EG"
      }
    ]

    assert [%{object_name: "AI-1", description: "Raumtemperatur EG"}] =
             SubscriptionTable.enrich_subscriptions([sub], objects)
  end

  test "filtered_subscriptions matches object, description, property, and value" do
    sub_match = %{
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :present_value,
      object_name: "AI-1",
      description: "Raumtemperatur EG",
      last_value_formatted: "21.5"
    }

    sub_other = %{
      object_id: %ObjectIdentifier{type: :binary_input, instance: 2},
      property: :present_value,
      object_name: "BI-2",
      description: "Türstatus",
      last_value_formatted: "0"
    }

    assert SubscriptionTable.filtered_subscriptions([sub_match, sub_other], "raum") == [sub_match]

    assert SubscriptionTable.filtered_subscriptions([sub_match, sub_other], "present_value") ==
             [sub_match, sub_other]

    assert SubscriptionTable.filtered_subscriptions([sub_match, sub_other], "binary -tür") == []
  end

  test "sorted_subscriptions sorts by description" do
    sub_a = %{
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :present_value,
      description: "Zulu"
    }

    sub_b = %{
      object_id: %ObjectIdentifier{type: :analog_input, instance: 2},
      property: :present_value,
      description: "Alpha"
    }

    assert [^sub_b, ^sub_a] =
             SubscriptionTable.sorted_subscriptions([sub_a, sub_b], "description", :asc)
  end
end
