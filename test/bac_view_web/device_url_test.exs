defmodule BacViewWeb.DeviceUrlTest do
  use BacViewWeb.ConnCase, async: true

  alias BacViewWeb.DeviceUrl

  test "device_path without query params" do
    assert DeviceUrl.device_path(42) == "/devices/42"
  end

  test "device_path with tab" do
    assert DeviceUrl.device_path(42, tab: "objects") == "/devices/42?tab=objects"
  end

  test "device_path with search on default tab" do
    assert DeviceUrl.device_path(42, search: "temp") == "/devices/42?search=temp"
  end

  test "device_path with tab and search" do
    assert DeviceUrl.device_path(42, tab: "objects", search: "temp sensor") ==
             "/devices/42?tab=objects&search=temp+sensor"
  end

  test "object_path without search" do
    assert DeviceUrl.object_path(42, :analog_input, 1) ==
             "/devices/42/objects/analog_input/1"
  end

  test "device_object_path opens the device object properties view" do
    assert DeviceUrl.device_object_path(42, %{instance: 100}) ==
             "/devices/42/objects/device/100"
  end

  test "object_path with search" do
    assert DeviceUrl.object_path(42, :analog_input, 1, search: "temp") ==
             "/devices/42/objects/analog_input/1?search=temp"
  end

  test "normalize_search" do
    assert DeviceUrl.normalize_search(nil) == ""
    assert DeviceUrl.normalize_search("foo") == "foo"
    assert DeviceUrl.normalize_search(123) == ""
  end

  test "device_path with type filter" do
    assert DeviceUrl.device_path(42,
             tab: "objects",
             search: "wwsg",
             types: [:analog_input, :binary_value]
           ) ==
             "/devices/42?tab=objects&search=wwsg&types=analog_input%2Cbinary_value"
  end

  test "object_path with search and types" do
    assert DeviceUrl.object_path(42, :analog_input, 1, search: "wwsg", types: [:analog_input]) ==
             "/devices/42/objects/analog_input/1?search=wwsg&types=analog_input"
  end

  test "normalize_types" do
    assert DeviceUrl.normalize_types(nil) == []
    assert DeviceUrl.normalize_types("analog_input,trend_log") == [:analog_input, :trend_log]

    assert DeviceUrl.normalize_types([:binary_value, "analog_input"]) == [
             :binary_value,
             :analog_input
           ]

    assert DeviceUrl.normalize_types("not_a_bacnet_object_type_#{System.unique_integer()}") == []
  end

  test "encode_types" do
    assert DeviceUrl.encode_types([:binary_value, :analog_input]) == "analog_input,binary_value"
  end

  test "device_path with sort params" do
    assert DeviceUrl.device_path(42,
             tab: "objects",
             search: "wwsg",
             types: [:analog_input],
             sort: "name",
             dir: :desc
           ) ==
             "/devices/42?tab=objects&search=wwsg&types=analog_input&sort=name&dir=desc"
  end

  test "object_path with sort params" do
    assert DeviceUrl.object_path(42, :analog_input, 1,
             search: "wwsg",
             types: [:analog_input],
             sort: "present_value",
             dir: "asc"
           ) ==
             "/devices/42/objects/analog_input/1?search=wwsg&types=analog_input&sort=present_value&dir=asc"
  end

  test "normalize_sort_column and dir" do
    assert DeviceUrl.normalize_sort_column("name") == "name"
    assert DeviceUrl.normalize_sort_column("invalid") == nil
    assert DeviceUrl.normalize_sort_dir("desc") == :desc
  end

  test "device_path with status filter" do
    assert DeviceUrl.device_path(42,
             tab: "objects",
             search: "wwsg",
             types: [:analog_input],
             status: [:fault, :in_alarm]
           ) ==
             "/devices/42?tab=objects&search=wwsg&types=analog_input&status=fault%2Cin_alarm"
  end

  test "normalize_status and encode_status" do
    assert DeviceUrl.normalize_status(nil) == []
    assert DeviceUrl.normalize_status("fault,none") == [:fault, :none]
    assert DeviceUrl.normalize_status([:in_alarm, "overridden"]) == [:in_alarm, :overridden]
    assert DeviceUrl.normalize_status("invalid_flag") == []
    assert DeviceUrl.encode_status([:in_alarm, :fault]) == "fault,in_alarm"
  end

  test "normalize_alarm_view" do
    assert DeviceUrl.normalize_alarm_view(nil) == "event_information"
    assert DeviceUrl.normalize_alarm_view("active_alarms") == "active_alarms"
    assert DeviceUrl.normalize_alarm_view("invalid") == "event_information"
  end

  test "device_path with alarm_view on alarms tab" do
    assert DeviceUrl.device_path(42, tab: "alarms", alarm_view: "notifications") ==
             "/devices/42?tab=alarms&alarm_view=notifications"

    assert DeviceUrl.device_path(42, tab: "alarms", alarm_view: "event_information") ==
             "/devices/42?tab=alarms"
  end

  test "normalize_cov_view" do
    assert DeviceUrl.normalize_cov_view(nil) == "subscriptions"
    assert DeviceUrl.normalize_cov_view("notifications") == "notifications"
    assert DeviceUrl.normalize_cov_view("invalid") == "subscriptions"
  end

  test "normalize_tab" do
    assert DeviceUrl.normalize_tab(nil) == "hierarchy"
    assert DeviceUrl.normalize_tab("objects") == "objects"
    assert DeviceUrl.normalize_tab("invalid") == "hierarchy"
  end

  test "object_path with tab preserves return view" do
    assert DeviceUrl.object_path(42, :analog_input, 1, tab: "objects", search: "temp") ==
             "/devices/42/objects/analog_input/1?tab=objects&search=temp"
  end

  test "normalize_hierarchy_view and path" do
    assert DeviceUrl.normalize_hierarchy_view(nil) == "explorer"
    assert DeviceUrl.normalize_hierarchy_view("tree") == "tree"

    assert DeviceUrl.normalize_hierarchy_path("structured_view:1/structured_view:2") == [
             {:structured_view, 1},
             {:structured_view, 2}
           ]
  end

  test "device_path with hierarchy_view and h_path" do
    assert DeviceUrl.device_path(42,
             tab: "hierarchy",
             hierarchy_view: "tree",
             hierarchy_path: [{:structured_view, 1}]
           ) == "/devices/42?hierarchy_view=tree&h_path=structured_view%3A1"
  end

  test "device_path with cov_view on subscriptions tab" do
    assert DeviceUrl.device_path(42, tab: "subscriptions", cov_view: "notifications") ==
             "/devices/42?tab=subscriptions&cov_view=notifications"

    assert DeviceUrl.device_path(42, tab: "subscriptions", cov_view: "subscriptions") ==
             "/devices/42?tab=subscriptions"
  end
end
