defmodule BacView.BACnet.DeviceSessionTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.DeviceSession

  test "refresh_object_from_properties updates cached object summary fields" do
    stale_flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: false,
      out_of_service: false
    }

    fresh_flags = %StatusFlags{
      in_alarm: false,
      fault: true,
      overridden: false,
      out_of_service: false
    }

    object = %{
      type: :analog_input,
      instance: 1,
      name: "Old Name",
      present_value: 10.0,
      present_value_formatted: "10.0",
      status_flags: stale_flags,
      units: :degrees_celsius,
      updated_at: ~U[2020-01-01 00:00:00Z]
    }

    properties = [
      %{
        property: :object_name,
        value: "Fresh Name"
      },
      %{
        property: :present_value,
        value: 42.5,
        type: "REAL"
      },
      %{
        property: :status_flags,
        value: fresh_flags
      },
      %{
        property: :units,
        value: :degrees_fahrenheit
      }
    ]

    refreshed = DeviceSession.refresh_object_from_properties(object, properties)

    assert refreshed.name == "Fresh Name"
    assert refreshed.present_value == 42.5
    assert refreshed.present_value_formatted == "42.5 °F"
    assert refreshed.status_flags == fresh_flags
    assert refreshed.units == :degrees_fahrenheit
    assert %DateTime{} = refreshed.updated_at
    assert DateTime.compare(refreshed.updated_at, object.updated_at) == :gt
  end

  test "refresh_object_from_properties updates updated_at for device objects" do
    object = %{
      type: :device,
      instance: 1,
      name: "BACnet Device",
      updated_at: ~U[2020-01-01 00:00:00Z]
    }

    properties = [
      %{property: :object_name, value: "BACnet Device"},
      %{property: :description, value: "Controller"}
    ]

    refreshed = DeviceSession.refresh_object_from_properties(object, properties)

    assert refreshed.description == "Controller"
    assert %DateTime{} = refreshed.updated_at
    assert DateTime.compare(refreshed.updated_at, object.updated_at) == :gt
  end

  test "loaded_snapshot returns live objects instead of stale device embed" do
    stale_flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: false,
      out_of_service: true
    }

    fresh_flags = %StatusFlags{
      in_alarm: false,
      fault: false,
      overridden: false,
      out_of_service: true
    }

    object = %{
      type: :binary_value,
      instance: 1,
      status_flags: stale_flags,
      present_value: true
    }

    device = %{
      id: 42,
      objects: [Map.put(object, :status_flags, stale_flags)],
      hierarchy: %{roots: [], empty?: true}
    }

    live_objects = [
      object
      |> Map.put(:status_flags, fresh_flags)
      |> Map.put(:present_value, false)
    ]

    snapshot =
      DeviceSession.loaded_snapshot(%{
        device: device,
        objects: live_objects,
        hierarchy: %{roots: [], empty?: true, structured_view_count: 0}
      })

    assert [%{status_flags: ^fresh_flags, present_value: false}] = snapshot.objects
    assert snapshot.object_count == 1
  end
end
