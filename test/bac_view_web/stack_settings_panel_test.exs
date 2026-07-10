defmodule BacViewWeb.StackSettingsPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacViewWeb.StackSettingsPanel

  test "renders offline stack status with startup error" do
    stack_status = %{
      running?: false,
      last_error:
        {{:shutdown, {:failed_to_start_child, BACnet.Stack.Transport.MstpTransport, :eacces}},
         {:child, :undefined, BacView.BACnet.Stack.Runtime, :start_link, :temporary, false,
          :infinity, :supervisor, [BacView.BACnet.Stack.Runtime]}}
    }

    settings = %{
      transport: "mstp",
      interface: "ttyS0",
      interface_error: nil
    }

    html =
      render_component(&StackSettingsPanel.stack_settings_panel/1,
        form: stack_form("mstp"),
        settings: settings,
        stack_status: stack_status,
        interface_options: [%{value: "ttyS0", label: "ttyS0"}],
        locale: "de",
        locale_version: 0
      )

    assert html =~ "Offline"
    assert html =~ ErrorMessage.format_reason(stack_status.last_error)
    assert html =~ ~s/id="stack-status-error"/
  end

  test "renders active stack status without error" do
    html =
      render_component(&StackSettingsPanel.stack_settings_panel/1,
        form: stack_form("ipv4"),
        settings: %{transport: "ipv4", interface: "lo", interface_error: nil},
        stack_status: %{running?: true, last_error: nil},
        interface_options: [%{value: "lo", label: "lo"}],
        locale: "de",
        locale_version: 0
      )

    assert html =~ "Aktiv"
    refute html =~ ~s/id="stack-status-error"/
    assert html =~ ~s/id="stack-settings-refresh-interfaces-btn"/
    assert html =~ "UDP-Port"
    assert html =~ "COV-Inkrement"
    assert html =~ "COV-Lifetime (Sek.)"
  end

  defp stack_form(transport) do
    params = %{
      "transport" => transport,
      "interface" => "ttyS0",
      "device_id" => "4194302",
      "ipv4_port" => "47808",
      "cov_lifetime_seconds" => "3600",
      "cov_increment" => "",
      "cov_confirmed" => "false",
      "network_number" => "1",
      "mstp_local_address" => "127",
      "mstp_baud_rate" => "auto"
    }

    Phoenix.Component.to_form(params, as: :stack)
  end
end
