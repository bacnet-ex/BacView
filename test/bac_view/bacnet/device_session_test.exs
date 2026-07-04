defmodule BacView.BACnet.DeviceSessionTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.DeviceSession

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
