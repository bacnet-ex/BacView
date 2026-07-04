defmodule BacViewWeb.DashboardLiveScanTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  setup do
    on_exit(fn ->
      path = Application.get_env(:bacview, :runtime_settings_path)
      if path, do: File.rm(path)
    end)

    :ok
  end

  test "scan form uses LiveView submit", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "phx-submit=\"scan_network\""
    assert has_element?(view, "#scan-network-form")
    assert has_element?(view, "#scan-network-form-submit")

    refute has_element?(view, "#scan-network-form-submit[disabled]")

    view
    |> form("#scan-network-form")
    |> render_submit()

    assert has_element?(view, "#scan-network-form-submit[disabled]")
    assert has_element?(view, "#scan_timeout_ms[disabled]")
  end

  test "scan submit via form enter still works", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#scan-network-form", %{
      "scan" => %{
        "timeout_ms" => "5000",
        "target_ip" => "",
        "device_id_low" => "",
        "device_id_high" => "",
        "vendor_id" => ""
      }
    })
    |> render_submit()

    assert has_element?(view, "#scan-network-form-submit[disabled]")
  end

  test "stack settings panel is rendered", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "stack-settings-panel"
    assert has_element?(view, "#stack-settings-form")
    assert has_element?(view, "#stack-settings-apply-btn")
    assert has_element?(view, "#stack-settings-refresh-interfaces-btn")
  end

  test "refresh interfaces button reloads interface options", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "stack_settings_refresh_interfaces")

    assert has_element?(view, "#stack-settings-form")
    assert has_element?(view, "#stack-settings-refresh-interfaces-btn")
  end

  test "stack settings save without restart returns valid LiveView response", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    settings = BacView.Settings.get()

    html =
      view
      |> form("#stack-settings-form", %{
        "stack" => %{
          "transport" => settings.transport,
          "interface" => settings.interface,
          "device_id" => Integer.to_string(settings.device_id),
          "network_number" => Integer.to_string(settings.network_number),
          "cov_lifetime_seconds" => "1800",
          "cov_confirmed" => "false"
        }
      })
      |> render_submit()

    refute html =~ "Ungültige Stack-Einstellungen"
    assert html =~ "Stack-Einstellungen gespeichert"
  end

  test "stack settings save works for ipv4 without mstp fields in submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    settings = BacView.Settings.get()

    view
    |> form("#stack-settings-form", %{"stack" => %{"transport" => "ipv4"}})
    |> render_change()

    interfaces = BacView.Settings.interface_options("ipv4")
    assert length(interfaces) >= 2

    current = settings.interface
    alt = Enum.find_value(interfaces, fn %{value: value} -> if value != current, do: value end)
    assert is_binary(alt)

    view
    |> form("#stack-settings-form", %{
      "stack" => %{
        "transport" => "ipv4",
        "interface" => alt,
        "device_id" => Integer.to_string(settings.device_id),
        "network_number" => Integer.to_string(settings.network_number),
        "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
        "cov_confirmed" => "false"
      }
    })
    |> render_submit()

    html = render(view)
    refute html =~ "Ungültige Stack-Einstellungen"

    if alt != current do
      assert has_element?(view, "#stack-settings-confirm-btn")
    else
      assert html =~ "Stack-Einstellungen gespeichert"
    end
  end

  test "bbmd status badge updates when registration status changes via pubsub", %{conn: conn} do
    assert {:ok, _} = BacView.Settings.update(transport: "ipv4")

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "bbmd-panel"

    registered = %{
      enabled: true,
      registration_status: :registered,
      bbmd: {{192, 168, 1, 1}, 47_808},
      bbmd_host: "192.168.1.1",
      bbmd_port: 47_808,
      ttl: 600,
      last_error: nil
    }

    send(view.pid, {:bbmd_updated, registered})

    html = render(view)
    assert html =~ "bac-badge-success"
    assert html =~ "Registriert"
    assert html =~ "Aktiv: 192.168.1.1:47808"

    disabled = %{
      registered
      | enabled: false,
        registration_status: :disabled,
        bbmd: nil,
        bbmd_host: nil,
        bbmd_port: nil
    }

    send(view.pid, {:bbmd_updated, disabled})

    html = render(view)
    refute html =~ "bac-badge-success"
    assert html =~ "bac-badge-ghost"
    assert html =~ "Inaktiv"
    refute html =~ "Aktiv: 192.168.1.1:47808"

    stale_disabled = %{
      registered
      | enabled: false,
        registration_status: :disabled,
        bbmd: {{192, 168, 1, 1}, 47_808}
    }

    send(view.pid, {:bbmd_updated, stale_disabled})

    html = render(view)
    assert html =~ "Inaktiv"
    refute html =~ "Aktiv: 192.168.1.1:47808"
  end

  test "clear device list button is disabled when empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#device-list-clear-btn[disabled]")
  end

  test "clear device list removes devices and resets search", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    device = %{
      id: 42,
      instance: 42,
      name: "Test Device",
      status: :discovered,
      vendor_id: 0,
      ip: "127.0.0.1",
      port: 47_808,
      object_count: nil
    }

    send(view.pid, {:devices_updated, [device]})
    render(view)

    refute has_element?(view, "#device-list-clear-btn[disabled]")

    render_click(view, "clear_devices")

    assert render(view) =~ "Geräteliste geleert"
    assert has_element?(view, "#device-list-clear-btn[disabled]")
    assert render(view) =~ "Noch keine Geräte gefunden"
  end

  test "r shortcut disables scan form while scanning", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#scan-network-form-submit[disabled]")

    render_click(view, "global_keydown", %{"key" => "r"})

    assert has_element?(view, "#scan-network-form-submit[disabled]")
    assert has_element?(view, "#scan_timeout_ms[disabled]")
  end
end
