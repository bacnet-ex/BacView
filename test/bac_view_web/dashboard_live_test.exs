defmodule BacViewWeb.DashboardLiveScanTest do
  use BacViewWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  setup do
    {:ok, _} =
      BacView.Settings.update(
        transport: "ipv4",
        interface: first_ipv4_interface(),
        ipv4_port: BacView.Settings.defaults().ipv4_port,
        mstp_local_address: BacView.Settings.defaults().mstp_local_address,
        mstp_baud_rate: BacView.Settings.defaults().mstp_baud_rate
      )

    on_exit(fn ->
      path = Application.get_env(:bacview, :runtime_settings_path)
      if path, do: File.rm(path)

      BacView.BACnet.Discovery.set_acceptance_filters(
        low_limit: nil,
        high_limit: nil,
        vendor_id: nil
      )

      {:ok, _} =
        BacView.Settings.update(
          transport: "ipv4",
          interface: first_ipv4_interface(),
          ipv4_port: BacView.Settings.defaults().ipv4_port,
          mstp_local_address: BacView.Settings.defaults().mstp_local_address,
          mstp_baud_rate: BacView.Settings.defaults().mstp_baud_rate
        )
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

  test "scan form restore event restores persisted values", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#scan-network-form")
    |> render_hook("scan_form_restore", %{
      "scan" => %{
        "timeout_ms" => "8000",
        "target_ip" => "10.0.0.1",
        "device_id_low" => "100",
        "device_id_high" => "200",
        "vendor_id" => "42"
      }
    })

    assert has_element?(view, "#scan_timeout_ms[value='8000']")
    assert has_element?(view, "#scan_target_ip[value='10.0.0.1']")
    assert has_element?(view, "#scan_device_id_low[value='100']")
    assert has_element?(view, "#scan_device_id_high[value='200']")
    assert has_element?(view, "#scan_vendor_id[value='42']")
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
    assert has_element?(view, "#stack-settings-restart-btn")
    assert has_element?(view, "#stack-settings-refresh-interfaces-btn")
  end

  test "stack restart button shows confirm then restarts", %{conn: conn} do
    alias BacView.BACnet.Stack

    start_supervised!(Stack)

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#stack-settings-restart-btn")
    refute has_element?(view, "#stack-settings-restart-confirm")

    render_click(view, "stack_restart_request")

    assert has_element?(view, "#stack-settings-restart-confirm")
    assert has_element?(view, "#stack-settings-confirm-btn")
    refute has_element?(view, "#stack-settings-apply-btn")

    # Restart may fail with eaddrinuse when the app stack already holds the port;
    # capture expected Boot/stack warnings so they do not leak into the suite log.
    parent = self()

    _log =
      capture_log(fn ->
        render_click(view, "stack_settings_confirm_restart")

        html =
          Enum.reduce_while(1..30, render(view), fn _attempt, html ->
            if html =~ "BACnet-Stack neu gestartet" or html =~ "Stack-Neustart fehlgeschlagen" do
              {:halt, html}
            else
              Process.sleep(50)
              {:cont, render(view)}
            end
          end)

        send(parent, {:stack_restart_html, html})
      end)

    assert_receive {:stack_restart_html, html}
    assert html =~ "BACnet-Stack neu gestartet" or html =~ "Stack-Neustart fehlgeschlagen"
    assert has_element?(view, "#stack-settings-restart-btn")
    refute has_element?(view, "#stack-settings-restart-confirm")
  end

  test "stack restart request can be cancelled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "stack_restart_request")
    assert has_element?(view, "#stack-settings-restart-confirm")

    render_click(view, "stack_settings_cancel_restart")

    refute has_element?(view, "#stack-settings-restart-confirm")
    assert has_element?(view, "#stack-settings-restart-btn")
    assert has_element?(view, "#stack-settings-apply-btn")
  end

  test "stack settings panel updates when network number is learned", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#stack-settings-learned-network")

    send(view.pid, {:network_number_updated, %{learned: 100, quality: :learned}})
    _html = render(view)

    assert has_element?(view, "#stack-settings-learned-network")
    assert render(view) =~ "100"
  end

  test "refresh interfaces button reloads interface options", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "stack_settings_refresh_interfaces")

    assert has_element?(view, "#stack-settings-form")
    assert has_element?(view, "#stack-settings-refresh-interfaces-btn")
  end

  test "stack settings save retries start when stack is offline due to error", %{conn: conn} do
    alias BacView.BACnet.Stack
    alias BacView.BACnet.Stack.Boot

    start_supervised!(Stack)

    assert {:ok, _} =
             BacView.Settings.update(
               transport: "mstp",
               interface: "ttyS0",
               mstp_local_address: 127,
               mstp_baud_rate: :auto
             )

    _log =
      capture_log(fn ->
        assert {:error, _} = Boot.start_runtime()
      end)

    refute Stack.running?()
    assert Stack.last_error() != nil

    assert {:ok, settings} = BacView.Settings.update(transport: "ipv4", ipv4_port: 48_124)

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ ~s/id="stack-status-error"/

    view
    |> form("#stack-settings-form", %{
      "stack" => %{
        "transport" => settings.transport,
        "interface" => settings.interface,
        "device_id" => Integer.to_string(settings.device_id),
        "network_number" => Integer.to_string(settings.network_number),
        "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
        "cov_confirmed" => "false"
      }
    })
    |> render_submit()

    html =
      Enum.reduce_while(1..20, render(view), fn _attempt, html ->
        if html =~ "BACnet-Stack neu gestartet" or html =~ "Stack-Neustart fehlgeschlagen" do
          {:halt, html}
        else
          Process.sleep(50)
          {:cont, render(view)}
        end
      end)

    assert html =~ "BACnet-Stack neu gestartet" or html =~ "Stack-Neustart fehlgeschlagen"
  end

  test "stack settings save persists cov_increment", %{conn: conn} do
    assert {:ok, _} = BacView.Settings.update(cov_increment: 0.1)

    {:ok, view, html} = live(conn, ~p"/")
    settings = BacView.Settings.get()

    assert html =~ "0.1"
    refute html =~ "e-01"

    view
    |> form("#stack-settings-form", %{
      "stack" => %{
        "transport" => settings.transport,
        "interface" => settings.interface,
        "device_id" => Integer.to_string(settings.device_id),
        "network_number" => Integer.to_string(settings.network_number),
        "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
        "cov_increment" => "0.5",
        "cov_confirmed" => "false",
        "scan_on_online" => "false"
      }
    })
    |> render_submit()

    assert BacView.Settings.get().cov_increment == 0.5

    view
    |> form("#stack-settings-form", %{
      "stack" => %{
        "transport" => settings.transport,
        "interface" => settings.interface,
        "device_id" => Integer.to_string(settings.device_id),
        "network_number" => Integer.to_string(settings.network_number),
        "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
        "cov_increment" => "",
        "cov_confirmed" => "false",
        "scan_on_online" => "false"
      }
    })
    |> render_submit()

    assert BacView.Settings.get().cov_increment == nil
  end

  test "stack settings save persists scan_on_online", %{conn: conn} do
    assert {:ok, _} = BacView.Settings.update(scan_on_online: false)

    {:ok, view, html} = live(conn, ~p"/")
    settings = BacView.Settings.get()

    assert html =~ "Geräte scannen, wenn sie online gehen"
    assert has_element?(view, "#stack_scan_on_online")

    view
    |> form("#stack-settings-form", %{
      "stack" => %{
        "transport" => settings.transport,
        "interface" => settings.interface,
        "device_id" => Integer.to_string(settings.device_id),
        "network_number" => Integer.to_string(settings.network_number),
        "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
        "cov_confirmed" => "false",
        "scan_on_online" => "true"
      }
    })
    |> render_submit()

    assert BacView.Settings.get().scan_on_online
    assert BacView.Settings.scan_on_online?()

    view
    |> form("#stack-settings-form", %{
      "stack" => %{
        "transport" => settings.transport,
        "interface" => settings.interface,
        "device_id" => Integer.to_string(settings.device_id),
        "network_number" => Integer.to_string(settings.network_number),
        "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
        "cov_confirmed" => "false",
        "scan_on_online" => "false"
      }
    })
    |> render_submit()

    refute BacView.Settings.get().scan_on_online
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

  defp first_ipv4_interface do
    case BacView.Settings.interface_options("ipv4") do
      [%{value: value} | _] -> value
      _ -> "lo"
    end
  end
end
