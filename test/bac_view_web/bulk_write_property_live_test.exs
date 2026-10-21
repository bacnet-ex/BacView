defmodule BacViewWeb.BulkWritePropertyLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSessionSupervisor
  alias BacView.Test.BacnetEtsLock

  @device_id 4242

  @cache_tables [
    {:bacview_devices, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_objects, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_properties, [:named_table, :set, :public, read_concurrency: true]}
  ]

  setup do
    previous_fun = Application.get_env(:bacview, :bulk_property_write_fun)
    previous_sync = Application.get_env(:bacview, :bulk_property_write_sync)

    Application.put_env(:bacview, :bulk_property_write_sync, true)

    # Test config does not start BacView.BACnet.Cache. Successful writes still
    # publish into the device session, which looks up these tables.
    BacnetEtsLock.reset_tables!(@cache_tables)
    :ets.insert(:bacview_devices, {@device_id, device()})

    on_exit(fn ->
      restore_env(:bulk_property_write_fun, previous_fun)
      restore_env(:bulk_property_write_sync, previous_sync)
      stop_session()
      BacnetEtsLock.delete_tables!(@cache_tables)
    end)

    :ok
  end

  test "writes one property to every selected object and shows the result", %{conn: conn} do
    test_pid = self()

    Application.put_env(:bacview, :bulk_property_write_fun, fn _device_id,
                                                               object_id,
                                                               property,
                                                               value,
                                                               opts ->
      send(test_pid, {:wrote, object_id, property, value, opts})
      :ok
    end)

    {:ok, view, _html} = live(conn, ~p"/devices/#{@device_id}?tab=objects")
    send(view.pid, {:device_load_done, {:ok, loaded_device()}})
    assert has_element?(view, "#object-analog_input-1")

    select_object(view, :analog_input, 1)
    select_object(view, :binary_value, 2)
    render_click(element(view, "#open-bulk-write-property"))

    assert has_element?(view, "#bulk-write-property-modal")
    assert has_element?(view, "#bulk-write-property option[value=present_value]")
    assert has_element?(view, "#bulk-write-property option[value=description]")
    refute has_element?(view, "#bulk-write-property option[value=object_name]")
    refute has_element?(view, "#bulk-write-property option[value=cov_increment]")
    assert has_element?(view, "#bulk-write-row-analog_input-1")
    assert has_element?(view, "#bulk-write-row-binary_value-2")
    assert has_element?(view, "#bulk-write-status-analog_input-1[data-status=ready]")

    view
    |> form("#bulk-write-property-form", %{
      bulk_write: %{property: "description", value: "Halle"}
    })
    |> render_submit()

    assert_receive {:wrote, %ObjectIdentifier{type: :analog_input, instance: 1}, :description,
                    "Halle", []}

    assert_receive {:wrote, %ObjectIdentifier{type: :binary_value, instance: 2}, :description,
                    "Halle", []}

    assert has_element?(view, "#bulk-write-status-analog_input-1[data-status=ok]")
    assert has_element?(view, "#bulk-write-status-binary_value-2[data-status=ok]")
    assert has_element?(view, "#bulk-write-summary", "2 geschrieben, 0 fehlgeschlagen")
  end

  test "shows the BACnet error returned for an object", %{conn: conn} do
    Application.put_env(:bacview, :bulk_property_write_fun, fn _device_id,
                                                               object_id,
                                                               _property,
                                                               _value,
                                                               _opts ->
      if object_id.instance == 2, do: {:error, :timeout}, else: :ok
    end)

    view = open_selection(conn)

    view
    |> form("#bulk-write-property-form", %{
      bulk_write: %{property: "description", value: "Halle"}
    })
    |> render_submit()

    assert has_element?(view, "#bulk-write-status-analog_input-1[data-status=ok]")
    assert has_element?(view, "#bulk-write-status-binary_value-2[data-status=error]")
    assert has_element?(view, "#bulk-write-status-binary_value-2", "Zeitüberschreitung")
    assert has_element?(view, "#bulk-write-summary", "1 geschrieben, 1 fehlgeschlagen")
  end

  test "parses the same text per object and keeps priority for commandable present values", %{
    conn: conn
  } do
    test_pid = self()

    Application.put_env(:bacview, :bulk_property_write_fun, fn _device_id,
                                                               object_id,
                                                               property,
                                                               value,
                                                               opts ->
      send(test_pid, {:wrote, object_id, property, value, opts})
      :ok
    end)

    view = open_selection(conn)

    view
    |> form("#bulk-write-property-form", %{
      bulk_write: %{property: "present_value", value: "1", priority: "8"}
    })
    |> render_submit()

    assert_receive {:wrote, %ObjectIdentifier{type: :analog_input, instance: 1}, :present_value,
                    1.0, opts}

    assert opts[:priority] == 8

    assert_receive {:wrote, %ObjectIdentifier{type: :binary_value, instance: 2}, :present_value,
                    true, []}

    assert has_element?(view, "#bulk-write-status-analog_input-1[data-status=ok]")
    assert has_element?(view, "#bulk-write-status-binary_value-2[data-status=ok]")
  end

  test "shows a parse error without calling the device", %{conn: conn} do
    test_pid = self()

    Application.put_env(:bacview, :bulk_property_write_fun, fn _device_id,
                                                               object_id,
                                                               property,
                                                               value,
                                                               opts ->
      send(test_pid, {:wrote, object_id, property, value, opts})
      :ok
    end)

    view = open_selection(conn)

    view
    |> form("#bulk-write-property-form", %{
      bulk_write: %{property: "present_value", value: "abc"}
    })
    |> render_submit()

    refute_receive {:wrote, _, _, _, _}, 50

    assert has_element?(
             view,
             "#bulk-write-status-analog_input-1[data-status=error]",
             "erwartet Zahl"
           )

    assert has_element?(
             view,
             "#bulk-write-status-binary_value-2[data-status=error]",
             "erwartet true/false"
           )
  end

  test "escape closes the dialog", %{conn: conn} do
    view = open_selection(conn)

    render_click(view, "global_keydown", %{
      "key" => "Escape",
      "code" => "Escape",
      "shift" => false
    })

    refute has_element?(view, "#bulk-write-property-modal")
  end

  test "close is ignored while a write is running", %{conn: conn} do
    test_pid = self()
    Application.put_env(:bacview, :bulk_property_write_sync, false)

    Application.put_env(:bacview, :bulk_property_write_fun, fn _device_id,
                                                               _object_id,
                                                               _property,
                                                               _value,
                                                               _opts ->
      send(test_pid, :entered)
      Process.sleep(200)
      send(test_pid, :finished)
      :ok
    end)

    {:ok, view, _html} = live(conn, ~p"/devices/#{@device_id}?tab=objects")
    send(view.pid, {:device_load_done, {:ok, loaded_device()}})
    select_object(view, :analog_input, 1)
    render_click(element(view, "#open-bulk-write-property"))

    view
    |> form("#bulk-write-property-form", %{
      bulk_write: %{property: "description", value: "Halle"}
    })
    |> render_submit()

    assert_receive :entered, 1_000
    render_click(view, "close_bulk_write_property")
    assert has_element?(view, "#bulk-write-property-modal")

    assert_receive :finished, 1_000
    Process.sleep(50)
    render(view)

    assert has_element?(view, "#bulk-write-property-modal")
    assert has_element?(view, "#bulk-write-status-analog_input-1[data-status=ok]")
  end

  defp open_selection(conn) do
    {:ok, view, _html} = live(conn, ~p"/devices/#{@device_id}?tab=objects")
    send(view.pid, {:device_load_done, {:ok, loaded_device()}})
    select_object(view, :analog_input, 1)
    select_object(view, :binary_value, 2)
    render_click(element(view, "#open-bulk-write-property"))
    view
  end

  defp select_object(view, type, instance) do
    render_click(
      element(view, "#object-#{type}-#{instance} td[phx-click=toggle_object_selection]")
    )
  end

  defp device do
    %{
      id: @device_id,
      instance: @device_id,
      address: {{192, 168, 1, 10}, 47_808},
      ip: "192.168.1.10",
      port: 47_808,
      max_apdu: 480,
      segmentation: 0,
      vendor_id: 5,
      object: %ObjectIdentifier{type: :device, instance: @device_id},
      status: :discovered,
      object_count: nil,
      name: "Test Device",
      loaded_at: nil,
      discovered_at: DateTime.utc_now()
    }
  end

  defp loaded_device do
    objects = [
      %{
        type: :analog_input,
        instance: 1,
        name: "AI-1",
        present_value: 1.0,
        present_value_formatted: "1.0",
        description: nil,
        commandable: true,
        writable: true,
        updated_at: nil
      },
      %{
        type: :binary_value,
        instance: 2,
        name: "BV-2",
        present_value: false,
        present_value_formatted: "false",
        description: nil,
        commandable: false,
        writable: true,
        updated_at: nil
      }
    ]

    Map.merge(device(), %{
      objects: objects,
      hierarchy: %{
        roots: [],
        empty?: true,
        structured_view_count: 0,
        source: :structured,
        split: nil
      },
      from_cache: true
    })
  end

  defp restore_env(key, nil), do: Application.delete_env(:bacview, key)
  defp restore_env(key, value), do: Application.put_env(:bacview, key, value)

  defp stop_session do
    case DeviceSessionSupervisor.session_pid(@device_id) do
      pid when is_pid(pid) ->
        _terminate_result = DynamicSupervisor.terminate_child(DeviceSessionSupervisor, pid)
        :ok

      _missing ->
        :ok
    end
  end
end
