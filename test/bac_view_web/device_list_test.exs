defmodule BacViewWeb.DeviceListTest do
  use ExUnit.Case, async: true

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
end
