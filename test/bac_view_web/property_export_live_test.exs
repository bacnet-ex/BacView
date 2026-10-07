defmodule BacViewWeb.PropertyExportLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSessionSupervisor
  alias BacView.Test.BacnetEtsLock
  alias BacViewWeb.PropertyExportLive

  setup do
    loaded_a = device_fixture(10, :loaded, "AHU", 2)
    loaded_b = device_fixture(12, :loaded, "Boiler", 1)
    discovered = device_fixture(11, :discovered, "Pending", nil)

    BacnetEtsLock.reset_tables!([:bacview_devices])
    :ets.insert(:bacview_devices, {10, loaded_a})
    :ets.insert(:bacview_devices, {11, discovered})
    :ets.insert(:bacview_devices, {12, loaded_b})

    {:ok, pid_a} = DeviceSessionSupervisor.ensure_session(10)
    {:ok, pid_b} = DeviceSessionSupervisor.ensure_session(12)

    :sys.replace_state(pid_a, fn state ->
      %{
        state
        | scanned: [
            object(:analog_input, 1, %{
              object_name: "Temp",
              present_value: 21.5,
              _unknown_properties: %{512 => "vendor"}
            }),
            object(:binary_input, 2, %{object_name: "Pump", present_value: true})
          ]
      }
    end)

    :sys.replace_state(pid_b, fn state ->
      %{
        state
        | scanned: [
            object(:analog_value, 3, %{object_name: "Setpoint", description: "Room"})
          ]
      }
    end)

    on_exit(fn ->
      terminate_session(pid_a)
      terminate_session(pid_b)
      BacnetEtsLock.delete_tables!([:bacview_devices])
    end)

    :ok
  end

  test "reconcile keeps hidden objects and adds objects from a newly selected device" do
    objects = [
      %{key: "10|analog_input|1", device_id: 10},
      %{key: "10|binary_input|2", device_id: 10},
      %{key: "12|analog_value|3", device_id: 12}
    ]

    assert PropertyExportLive.reconcile_objects(
             ["10|analog_input|1"],
             [10],
             [10, 12],
             objects
           ) == ["10|analog_input|1", "12|analog_value|3"]

    assert PropertyExportLive.reconcile_objects(
             ["10|analog_input|1", "10|binary_input|2"],
             [10, 12],
             [10],
             Enum.take(objects, 2)
           ) == ["10|analog_input|1", "10|binary_input|2"]
  end

  test "reconcile keeps unchecked properties and selects properties that newly appear" do
    old = [%{id: :present_value}, %{id: :description}]
    new = [%{id: :present_value}, %{id: :description}, %{id: :units}]

    assert PropertyExportLive.reconcile_properties([:present_value], old, new) == [
             :present_value,
             :units
           ]

    assert PropertyExportLive.reconcile_properties([:present_value], new, new) == [:present_value]
  end

  test "opens the property export dialog beside EDE export and read property", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#open-multi-ede-export-btn")
    assert has_element?(view, "#open-property-export-btn")
    assert has_element?(view, "#open-read-property-btn")
    refute has_element?(view, "#property-export-modal")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    assert has_element?(view, "#property-export-modal")
    assert has_element?(view, "#property-export-format-csv[checked]")
    assert has_element?(view, "#property-export-device-10[checked]")
    assert has_element?(view, "#property-export-device-11[disabled]")
    assert has_element?(view, "#property-export-device-12[checked]")
    assert has_element?(view, "#property-export-object-10-analog_input-1")
    refute has_element?(view, "#property-export-object-10-analog_input-1[checked]")
    refute has_element?(view, "#property-export-object-10-binary_input-2[checked]")
    refute has_element?(view, "#property-export-object-12-analog_value-3[checked]")
    assert has_element?(view, "#property-export-property-present_value")
    refute has_element?(view, "#property-export-property-present_value[checked]")
    refute has_element?(view, "#property-export-property-description[checked]")
    refute has_element?(view, "#property-export-property-512[checked]")
    assert has_element?(view, "#property-export-type-filter")
  end

  test "filtering by type keeps objects that are not visible selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> form("#property-export-form", form_params("binary_input", all_keys(), all_properties()))
    |> render_change()

    assert has_element?(view, "#property-export-object-10-binary_input-2[checked]")
    refute has_element?(view, "#property-export-object-10-analog_input-1")
    assert has_element?(view, "#property-export-hidden-object-10-analog_input-1")
    assert has_element?(view, "#property-export-hidden-object-12-analog_value-3")

    view
    |> element("#property-export-select-no-objects")
    |> render_click()

    refute has_element?(view, "#property-export-object-10-binary_input-2[checked]")
    assert has_element?(view, "#property-export-hidden-object-10-analog_input-1")
    assert has_element?(view, "#property-export-hidden-object-12-analog_value-3")

    view
    |> form(
      "#property-export-form",
      form_params("", ["10|analog_input|1", "12|analog_value|3"], all_properties())
    )
    |> render_change()

    assert has_element?(view, "#property-export-object-10-analog_input-1[checked]")
    refute has_element?(view, "#property-export-object-10-binary_input-2[checked]")
    assert has_element?(view, "#property-export-object-12-analog_value-3[checked]")
  end

  test "select all adds only the objects currently shown", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> element("#property-export-select-no-objects")
    |> render_click()

    view
    |> form("#property-export-form", form_params("analog_input", [], [""]))
    |> render_change()

    view
    |> element("#property-export-select-all-objects")
    |> render_click()

    assert has_element?(view, "#property-export-object-10-analog_input-1[checked]")
    refute has_element?(view, "#property-export-hidden-object-12-analog_value-3")

    view
    |> form(
      "#property-export-form",
      form_params("", ["10|analog_input|1"], ["present_value", "object_name", "512"])
    )
    |> render_change()

    assert has_element?(view, "#property-export-object-10-analog_input-1[checked]")
    refute has_element?(view, "#property-export-object-10-binary_input-2[checked]")
    refute has_element?(view, "#property-export-object-12-analog_value-3[checked]")
  end

  test "search hides objects and properties without changing the selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> form("#property-export-form", form_params("", all_keys(), all_properties()))
    |> render_change()

    view
    |> form(
      "#property-export-form",
      form_params("", all_keys(), all_properties(), ["10", "12"], %{"object_query" => "Pump"})
    )
    |> render_change()

    assert has_element?(view, "#property-export-object-search[value='Pump']")
    assert has_element?(view, "#property-export-object-10-binary_input-2[checked]")
    refute has_element?(view, "#property-export-object-10-analog_input-1")
    assert has_element?(view, "#property-export-hidden-object-10-analog_input-1")
    assert has_element?(view, "#property-export-hidden-object-12-analog_value-3")

    view
    |> form(
      "#property-export-form",
      form_params("", all_keys(), all_properties(), ["10", "12"], %{
        "object_query" => "Pump",
        "property_query" => "present"
      })
    )
    |> render_change()

    assert has_element?(view, "#property-export-property-present_value[checked]")
    refute has_element?(view, "#property-export-property-description")
    assert has_element?(view, "#property-export-hidden-property-description")
    assert has_element?(view, "#property-export-hidden-property-object_name")
    assert has_element?(view, "#property-export-object-10-binary_input-2[checked]")
  end

  test "select all visible objects respects the object search", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> form(
      "#property-export-form",
      form_params("", [""], [""], ["10", "12"], %{"object_query" => "Setpoint"})
    )
    |> render_change()

    view
    |> element("#property-export-select-all-objects")
    |> render_click()

    assert has_element?(view, "#property-export-object-12-analog_value-3[checked]")
    refute has_element?(view, "#property-export-object-10-analog_input-1")
    refute has_element?(view, "#property-export-hidden-object-10-analog_input-1")
  end

  test "properties follow the selected objects", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> form(
      "#property-export-form",
      form_params("", ["10|analog_input|1", "10|binary_input|2"], all_properties(), ["10"])
    )
    |> render_change()

    refute has_element?(view, "#property-export-object-12-analog_value-3")
    refute has_element?(view, "#property-export-property-description")
    assert has_element?(view, "#property-export-property-present_value")
    assert has_element?(view, "#property-export-property-512")
  end

  test "exports csv and json for the selected loaded devices", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> form(
      "#property-export-form",
      form_params("", all_keys(), ["present_value", "description", "object_name"])
    )
    |> render_submit()

    assert_push_event(view, "download_file", %{
      filename: "bacview-properties.csv",
      content: csv
    })

    assert csv =~ "present_value"
    assert csv =~ "Temp"
    assert csv =~ "Pump"
    assert csv =~ "Room"
    assert csv =~ "\"10\";\"analog_input\";\"1\";;\"Temp\";\"21.5\""
    refute has_element?(view, "#property-export-modal")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    view
    |> form(
      "#property-export-form",
      form_params("json", all_keys(), ["present_value", "description", "object_name"])
    )
    |> render_submit()

    assert_push_event(view, "download_file", %{
      filename: "bacview-properties.json",
      content: json
    })

    assert json =~ "\"present_value\": 21.5"
    assert json =~ "\"present_value\": null"
    assert json =~ "\"description\": null"
    assert json =~ "\"description\": \"Room\""
  end

  test "Escape closes the property export dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-property-export-btn")
    |> render_click()

    render_click(view, "global_keydown", %{
      "key" => "Escape",
      "code" => "Escape",
      "shift" => false
    })

    refute has_element?(view, "#property-export-modal")
  end

  test "the button is on the device and object pages", %{conn: conn} do
    {:ok, device_view, _html} = live(conn, ~p"/devices/11")
    assert has_element?(device_view, "#open-property-export-btn")

    {:ok, object_view, _html} = live(conn, ~p"/devices/11/objects/analog_input/1")
    assert has_element?(object_view, "#open-property-export-btn")
  end

  defp form_params(
         format_or_filter,
         object_keys,
         property_ids,
         device_ids \\ ["10", "12"],
         extras \\ %{}
       )

  defp form_params(format, object_keys, property_ids, device_ids, extras)
       when format in ["csv", "json"] do
    %{
      "property_export" =>
        Map.merge(
          %{
            "format" => format,
            "object_type" => "",
            "object_query" => "",
            "property_query" => "",
            "device_ids" => device_ids,
            "object_keys" => object_keys,
            "property_ids" => property_ids
          },
          extras
        )
    }
  end

  defp form_params(object_type, object_keys, property_ids, device_ids, extras) do
    %{
      "property_export" =>
        Map.merge(
          %{
            "format" => "csv",
            "object_type" => object_type,
            "object_query" => "",
            "property_query" => "",
            "device_ids" => device_ids,
            "object_keys" => object_keys,
            "property_ids" => property_ids
          },
          extras
        )
    }
  end

  defp all_keys() do
    ["10|analog_input|1", "10|binary_input|2", "12|analog_value|3"]
  end

  defp all_properties() do
    ["512", "description", "object_name", "present_value"]
  end

  defp object(type, instance, properties) do
    {%ObjectIdentifier{type: type, instance: instance}, properties}
  end

  defp device_fixture(id, status, name, object_count) do
    %{
      id: id,
      instance: id,
      address: {{192, 168, 1, id}, 47_808},
      ip: "192.168.1.#{id}",
      port: 47_808,
      max_apdu: 480,
      segmentation: 0,
      vendor_id: 5,
      object: %ObjectIdentifier{type: :device, instance: id},
      status: status,
      object_count: object_count,
      name: name,
      loaded_at: nil,
      discovered_at: DateTime.utc_now()
    }
  end

  defp terminate_session(pid) do
    if is_pid(pid) and Process.alive?(pid) do
      DynamicSupervisor.terminate_child(DeviceSessionSupervisor, pid)
    end

    :ok
  end
end
