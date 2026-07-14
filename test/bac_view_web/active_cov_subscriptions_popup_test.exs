defmodule BacViewWeb.ActiveCovSubscriptionsPopupTest do
  use BacViewWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.ActiveCovSubscriptionsPopup

  test "renders clickable cov badge" do
    html =
      render_component(&ActiveCovSubscriptionsPopup.active_cov_badge/1, %{
        count: 3,
        open: false,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s/id="active-cov-badge"/
    assert html =~ ~s/phx-click="toggle_cov_popup"/
    assert html =~ "3"
    assert html =~ "COV"
  end

  test "renders grouped device list with links to subscriptions tab" do
    html =
      render_component(&ActiveCovSubscriptionsPopup.active_cov_panel/1, %{
        open: true,
        grouped?: true,
        total_count: 3,
        device_groups: [
          %{
            device_id: 42,
            device_label: "AHU-1",
            device_description: "Air handling unit",
            count: 3,
            device_path: "/devices/42?tab=subscriptions"
          }
        ],
        locale: "de",
        locale_version: 0
      })

    document = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(document, "#active-cov-popup-device-list")) == 1
    assert Enum.count(LazyHTML.query(document, "#active-cov-device-42")) == 1
    assert html =~ ~s|href="/devices/42?tab=subscriptions"|
    assert html =~ "Air handling unit"
    refute html =~ "active-cov-popup-list"
  end

  test "renders popup entries with object link and chart button" do
    html =
      render_component(&ActiveCovSubscriptionsPopup.active_cov_panel/1, %{
        open: true,
        entries: [
          %{
            id: "42-analog_input-1-present_value",
            object_label: "analog_input:1",
            object_name: "Room Temp",
            description: nil,
            property_label: "present_value",
            value_label: "21.5 C",
            type: :analog_input,
            instance: 1,
            property: :present_value,
            chartable?: true,
            object_path: "/devices/42/objects/analog_input/1"
          }
        ],
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s/id="active-cov-popup"/
    assert html =~ ~s/id="active-cov-entry-42-analog_input-1-present_value"/
    assert html =~ ~s|href="/devices/42/objects/analog_input/1"|
    assert html =~ ~s/id="cov-popup-chart-42-analog_input-1-present_value"/
    assert html =~ "open_cov_chart_modal"
    assert html =~ "21.5 C"
  end
end
