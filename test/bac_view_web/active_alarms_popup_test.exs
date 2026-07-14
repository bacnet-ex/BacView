defmodule BacViewWeb.ActiveAlarmsPopupTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.ActiveAlarmsPopup

  test "grouped panel renders device list at first level" do
    html =
      render_component(&ActiveAlarmsPopup.active_alarms_panel/1,
        open: true,
        grouped?: true,
        level: :devices,
        device_groups: [
          %{
            device_id: 42,
            device_label: "AHU-1",
            device_description: "Air handling unit",
            count: 2,
            sort_key: 1,
            device_path: "/devices/42"
          }
        ],
        entries: [],
        locale: "de",
        locale_version: 0
      )

    document = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(document, "#active-alarms-popup-device-list")) == 1
    assert Enum.count(LazyHTML.query(document, "#active-alarm-device-42")) == 1
    assert html =~ "Air handling unit"
    refute html =~ "active-alarms-popup-back"
    refute html =~ "active-alarms-popup-list"
  end

  test "grouped panel renders alarm entries at second level with back button" do
    html =
      render_component(&ActiveAlarmsPopup.active_alarms_panel/1,
        open: true,
        grouped?: true,
        level: :entries,
        selected_device_id: 42,
        device_groups: [
          %{
            device_id: 42,
            device_label: "AHU-1",
            count: 1,
            sort_key: 1,
            device_path: "/devices/42"
          }
        ],
        entries: [
          %{
            id: "42-analog_input-1",
            device_id: 42,
            device_label: "AHU-1",
            object_label: "analog_input:1",
            description: "Supply temp",
            alarm_since_label: "—",
            sort_key: 1,
            device_path: "/devices/42",
            object_path: "/devices/42/objects/analog_input/1"
          }
        ],
        locale: "de",
        locale_version: 0
      )

    document = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(document, "#active-alarms-popup-back")) == 1
    assert html =~ "AHU-1"
    assert Enum.count(LazyHTML.query(document, "#active-alarms-popup-list")) == 1
    refute html =~ "active-alarms-popup-device-list"
  end
end
