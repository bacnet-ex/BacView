defmodule BacViewWeb.DeviceListTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.DeviceList

  @vendor_names %{5 => "Example Vendor"}

  @devices [
    %{
      id: 1,
      instance: 1,
      name: "AHU-1",
      vendor_id: 5,
      ip: "192.168.1.10",
      port: 47_808,
      status: :loaded,
      object_count: 42
    },
    %{
      id: 2,
      instance: 2,
      name: nil,
      vendor_id: 9,
      ip: "192.168.1.20",
      port: 47_808,
      status: :discovered,
      object_count: nil
    }
  ]

  test "filtered_devices matches name and vendor" do
    assert length(DeviceList.filtered_devices(@devices, "ahu", @vendor_names)) == 1
    assert length(DeviceList.filtered_devices(@devices, "example", @vendor_names)) == 1
  end

  test "filtered_devices supports exclusion tokens" do
    assert length(DeviceList.filtered_devices(@devices, "-ahu", @vendor_names)) == 1
    assert length(DeviceList.filtered_devices(@devices, "192 -ahu", @vendor_names)) == 1
  end

  test "sorted_devices sorts by instance descending" do
    assert [2, 1] =
             DeviceList.sorted_devices(@devices, "instance", :desc, @vendor_names)
             |> Enum.map(& &1.instance)
  end

  test "list_devices sorts only in table view" do
    assert [1, 2] =
             DeviceList.list_devices(@devices, "", @vendor_names, "instance", :asc, :grid)
             |> Enum.map(& &1.instance)

    assert [2, 1] =
             DeviceList.list_devices(@devices, "", @vendor_names, "instance", :desc, :table)
             |> Enum.map(& &1.instance)
  end

  test "toggle_sort cycles sort direction" do
    assert DeviceList.toggle_sort(nil, :asc, "name") == {"name", :asc}
    assert DeviceList.toggle_sort("name", :asc, "name") == {"name", :desc}
    assert DeviceList.toggle_sort("name", :desc, "name") == {"name", :asc}
  end

  test "normalize_view" do
    assert DeviceList.normalize_view("table") == :table
    assert DeviceList.normalize_view("grid") == :grid
    assert DeviceList.normalize_view("invalid") == :grid
  end

  test "status labels include loading" do
    devices = [
      Map.put(Enum.at(@devices, 0), :status, :loading)
    ]

    html =
      render_component(&DeviceList.device_list/1,
        devices: devices,
        vendor_names: @vendor_names,
        view: :grid,
        locale: "de",
        locale_version: 0
      )

    assert html =~ "Wird geladen"
    assert html =~ "bac-badge-warning"
  end

  test "device cards show device description under object name" do
    devices = [
      Map.put(Enum.at(@devices, 0), :description, "Main air handler")
    ]

    html =
      render_component(&DeviceList.device_list/1,
        devices: devices,
        vendor_names: @vendor_names,
        view: :grid,
        locale: "de",
        locale_version: 0
      )

    assert html =~ "AHU-1"
    assert html =~ "Main air handler"
  end

  test "device cards show alarm and cov badges only when count is positive" do
    html =
      render_component(&DeviceList.device_list/1,
        devices: @devices,
        vendor_names: @vendor_names,
        view: :grid,
        device_badge_counts: %{alarms: %{1 => 2}, cov: %{1 => 3}},
        locale: "de",
        locale_version: 0
      )

    document = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(document, "#device-card-1 .bac-badge-error")) == 1

    assert Enum.count(
             LazyHTML.query(document, "#device-card-1 .bac-device-card-meta .bac-badge-success")
           ) == 1

    assert Enum.count(LazyHTML.query(document, "#device-card-2 .bac-badge-error")) == 0

    assert Enum.count(
             LazyHTML.query(document, "#device-card-2 .bac-device-card-meta .bac-badge-success")
           ) == 0
  end
end
