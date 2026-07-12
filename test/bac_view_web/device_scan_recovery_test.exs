defmodule BacViewWeb.DeviceScanRecoveryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.DeviceScanRecovery

  test "renders recovery actions for validation failures" do
    html =
      render_component(&DeviceScanRecovery.recovery_panel/1,
        scan_errors: [
          %{
            object: "multistate_value:1",
            object_id: %ObjectIdentifier{type: :multistate_value, instance: 1},
            message:
              "Eigenschaftswert entspricht nicht der BACnet-Spezifikation (present value).",
            reason: {:value_failed_property_validation, :present_value},
            recoverable: true,
            retry_modes: [:value, true]
          },
          %{
            object: "analog_input:2",
            object_id: %ObjectIdentifier{type: :analog_input, instance: 2},
            message: "Eigenschaftswert hat einen ungültigen BACnet-Datentyp (present value).",
            reason: {:invalid_property_type, :present_value},
            recoverable: true,
            retry_modes: [true]
          }
        ],
        scan_retrying: %{},
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~s/id="device-scan-recovery-panel"/
    assert html =~ "2 Objekte konnten nicht gelesen werden"
    assert html =~ "multistate_value:1"
    assert html =~ ~s/id="device-scan-recovery-value-1"/
    assert html =~ ~s/id="device-scan-recovery-all-1"/
    assert html =~ ~s/phx-value-skip-mode="value"/
    assert html =~ ~s/phx-value-skip-mode="all"/
    refute html =~ ~s/id="device-scan-recovery-value-2"/
    assert html =~ ~s/id="device-scan-recovery-all-2"/
  end

  test "does not render when there are no scan errors" do
    html =
      render_component(&DeviceScanRecovery.recovery_panel/1,
        scan_errors: [],
        scan_retrying: %{},
        locale: "de",
        locale_version: 0
      )

    refute html =~ ~s/id="device-scan-recovery-panel"/
  end
end
