defmodule BacViewWeb.MultiEdeExportLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSessionSupervisor
  alias BacView.Test.BacnetEtsLock
  alias BacViewWeb.MultiEdeExportLive

  setup do
    loaded_a = device_fixture(10, :loaded, "AHU", 1)
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
            {%ObjectIdentifier{type: :analog_input, instance: 1}, %{object_name: "Temp"}}
          ]
      }
    end)

    :sys.replace_state(pid_b, fn state ->
      %{
        state
        | scanned: [
            {%ObjectIdentifier{type: :binary_input, instance: 2}, %{object_name: "Pump"}}
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

  test "reconcile keeps the current selection and defaults types from a newly selected device" do
    old = [%{type: :analog_input, count: 1}]

    new = [
      %{type: :analog_input, count: 1},
      %{type: :file, count: 1},
      %{type: :binary_input, count: 1}
    ]

    assert MultiEdeExportLive.reconcile_object_types([:analog_input], old, new) == [
             :analog_input,
             :binary_input
           ]

    assert MultiEdeExportLive.reconcile_object_types([], new, new) == []
  end

  test "opens the multi-device EDE dialog beside read property", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#multi-ede-export-modal")

    view
    |> element("#open-multi-ede-export-btn")
    |> render_click()

    assert has_element?(view, "#multi-ede-export-modal")
    assert has_element?(view, "#multi-ede-export-form")
    assert has_element?(view, "#multi-ede-export-project-name")
    assert has_element?(view, "#multi-ede-export-version")
    assert has_element?(view, "#multi-ede-export-author")
    assert has_element?(view, "#multi-ede-export-include-state-texts")
    assert has_element?(view, "#multi-ede-export-device-10")
    assert has_element?(view, "#multi-ede-export-device-11[disabled]")
    assert has_element?(view, "#multi-ede-export-device-12")
    assert has_element?(view, "#multi-ede-export-type-analog_input")
    assert has_element?(view, "#multi-ede-export-type-binary_input")

    html = render(view)
    assert html =~ ~s(value="BacView")
    assert html =~ "Nur geladene Geräte können ausgewählt werden."
  end

  test "dropping a device removes object types that only that device has", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-multi-ede-export-btn")
    |> render_click()

    view
    |> form("#multi-ede-export-form", %{
      "ede_export" => %{
        "project_name" => "BacView",
        "version" => "1.0.0",
        "author" => "BacView",
        "device_ids" => ["10"],
        "object_types" => ["analog_input", "binary_input"]
      }
    })
    |> render_change()

    assert has_element?(view, "#multi-ede-export-type-analog_input")
    refute has_element?(view, "#multi-ede-export-type-binary_input")
  end

  test "exports the selected loaded devices into one EDE file", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-multi-ede-export-btn")
    |> render_click()

    view
    |> form("#multi-ede-export-form", %{
      "ede_export" => %{
        "project_name" => "Site",
        "version" => "1.2.0",
        "author" => "Ada",
        "include_state_texts" => "false",
        "device_ids" => ["10", "12"],
        "object_types" => ["analog_input", "binary_input"]
      }
    })
    |> render_submit()

    assert_push_event(view, "download_file", %{
      filename: "Site_EDE.csv",
      content: content
    })

    assert content =~ "PROJECT_NAME;Site"
    assert content =~ "VERSION_OF_REFERENCEFILE;1.2.0"
    assert content =~ "AUTHOR_OF_LAST_CHANGE;Ada"
    assert content =~ "10_Temp;10;Temp;0;1"
    assert content =~ "12_Pump;12;Pump;3;2"
    refute has_element?(view, "#multi-ede-export-modal")
  end

  test "Escape closes the multi-device EDE dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-multi-ede-export-btn")
    |> render_click()

    render_click(view, "global_keydown", %{
      "key" => "Escape",
      "code" => "Escape",
      "shift" => false
    })

    refute has_element?(view, "#multi-ede-export-modal")
  end

  test "the button is on the device and object pages", %{conn: conn} do
    {:ok, device_view, _html} = live(conn, ~p"/devices/11")
    assert has_element?(device_view, "#open-multi-ede-export-btn")

    {:ok, object_view, _html} = live(conn, ~p"/devices/11/objects/analog_input/1")
    assert has_element?(object_view, "#open-multi-ede-export-btn")
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
