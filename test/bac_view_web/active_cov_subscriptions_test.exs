defmodule BacViewWeb.ActiveCovSubscriptionsTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.ActiveCovSubscriptions

  test "builds popup entries with object paths and chart eligibility" do
    device_id = 42
    object_id = %ObjectIdentifier{type: :analog_input, instance: 1}

    subscriptions = [
      %{
        device_id: device_id,
        object_id: object_id,
        property: :present_value,
        last_value_formatted: "21.5 °C"
      }
    ]

    objects = [
      %{
        type: :analog_input,
        instance: 1,
        name: "Room Temp",
        description: "Zone 1 temperature"
      }
    ]

    [entry] =
      ActiveCovSubscriptions.list(
        device_id: device_id,
        subscriptions: subscriptions,
        objects: objects,
        list_opts: [tab: "hierarchy"]
      )

    assert entry.object_label == "analog_input:1"
    assert entry.object_name == "Room Temp"
    assert entry.description == "Zone 1 temperature"
    assert entry.property_label == "present_value"
    assert entry.value_label == "21.5 °C"
    assert entry.type == :analog_input
    assert entry.instance == 1
    assert entry.property == :present_value
    assert entry.object_path =~ "/devices/42/objects/analog_input/1"
    assert entry.object_path =~ "tab=subscriptions"
  end

  test "builds object paths with object-page return context" do
    device_id = 42
    object_id = %ObjectIdentifier{type: :analog_value, instance: 2}

    subscriptions = [
      %{
        device_id: device_id,
        object_id: object_id,
        property: :present_value,
        last_value_formatted: "50 %"
      }
    ]

    [entry] =
      ActiveCovSubscriptions.list(
        device_id: device_id,
        subscriptions: subscriptions,
        objects: [],
        list_opts: [
          tab: "objects",
          search: "zone",
          types: [:analog_value],
          status: [],
          sort: "object",
          dir: :asc,
          alarm_view: "event_information",
          cov_view: "subscriptions",
          hierarchy_view: "explorer",
          hierarchy_path: [],
          h_split: nil,
          device_id: device_id
        ]
      )

    assert entry.object_path =~ "/devices/42/objects/analog_value/2"
    assert entry.object_path =~ "tab=subscriptions"
    assert entry.object_path =~ "search=zone"
  end
end
