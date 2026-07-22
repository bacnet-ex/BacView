defmodule BacViewWeb.DeviceServicesMenuLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @device %{
    id: 42,
    instance: 42,
    address: {{192, 168, 1, 10}, 47_808},
    ip: "192.168.1.10",
    port: 47_808,
    max_apdu: 480,
    segmentation: 0,
    vendor_id: 5,
    object: %BACnet.Protocol.ObjectIdentifier{type: :device, instance: 42},
    status: :discovered,
    object_count: nil,
    name: "Test Device",
    loaded_at: nil,
    discovered_at: DateTime.utc_now()
  }

  setup do
    unless :ets.whereis(:bacview_devices) != :undefined do
      :ets.new(:bacview_devices, [:named_table, :set, :public, read_concurrency: true])
    end

    :ets.insert(:bacview_devices, {42, @device})

    on_exit(fn ->
      if :ets.whereis(:bacview_devices) != :undefined do
        :ets.delete_all_objects(:bacview_devices)
      end
    end)

    :ok
  end

  test "toggle via event params opens menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_click(view, "toggle_device_services_menu", %{"device_id" => "42"})

    assert html =~ "device-services-menu-42"
  end

  test "toggle opens device services menu on dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "device-services-trigger-42"
    refute has_element?(view, "#device-services-menu-42")

    html = view |> element("#device-services-trigger-42") |> render_click()

    assert html =~ "device-services-menu-42"
    assert html =~ "Zeitsynchronisation"
    assert has_element?(view, "#device-services-scan-42")
    assert html =~ "Gerät scannen"
  end

  test "toggle closes device services menu on second click", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#device-services-trigger-42") |> render_click()
    assert has_element?(view, "#device-services-menu-42")

    view |> element("#device-services-trigger-42") |> render_click()
    refute has_element?(view, "#device-services-menu-42")
  end

  test "scan device from dashboard menu closes menu and starts scan", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#device-services-trigger-42") |> render_click()
    assert has_element?(view, "#device-services-scan-42")

    html = view |> element("#device-services-scan-42") |> render_click()

    refute has_element?(view, "#device-services-menu-42")
    assert html =~ "Gerätescan gestartet."
  end
end
