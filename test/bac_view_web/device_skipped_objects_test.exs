defmodule BacViewWeb.DeviceSkippedObjectsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.DeviceSkippedObjects

  test "renders nothing when empty" do
    html =
      render_component(&DeviceSkippedObjects.skipped_panel/1, %{
        skipped_objects: [],
        locale: "de",
        locale_version: 0
      })

    refute html =~ ~s(id="device-skipped-objects")
  end

  test "renders count and object labels when skipped" do
    skipped = [
      %{
        object_id: %ObjectIdentifier{type: 900, instance: 1},
        type: 900,
        instance: 1,
        label: "900:1",
        reason: :unsupported_object_type
      },
      %{
        object_id: %ObjectIdentifier{type: 901, instance: 2},
        type: 901,
        instance: 2,
        label: "901:2",
        reason: :unsupported_object_type
      }
    ]

    html =
      render_component(&DeviceSkippedObjects.skipped_panel/1, %{
        skipped_objects: skipped,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(id="device-skipped-objects")
    assert html =~ "2 unbekannte/proprietäre Objekttypen übersprungen"
    assert html =~ "900:1"
    assert html =~ "901:2"
    assert html =~ ~s(id="device-skipped-object-1")
  end
end
