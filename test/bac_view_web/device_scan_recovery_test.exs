defmodule BacViewWeb.DeviceScanRecoveryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.DeviceScanRecovery

  @scan_errors [
    %{
      object: "multistate_value:1",
      object_id: %ObjectIdentifier{type: :multistate_value, instance: 1},
      message: "Eigenschaftswert entspricht nicht der BACnet-Spezifikation (present value).",
      reason: {:value_failed_property_validation, :present_value},
      recoverable: true,
      retry_modes: [:value, :ignore_invalid, true, :skip_all_and_ignore_invalid]
    },
    %{
      object: "analog_input:2",
      object_id: %ObjectIdentifier{type: :analog_input, instance: 2},
      message: "Eigenschaftswert hat einen ungültigen BACnet-Datentyp (present value).",
      reason: {:invalid_property_type, :present_value},
      recoverable: true,
      retry_modes: [:ignore_invalid, true, :skip_all_and_ignore_invalid]
    }
  ]

  defp render_recovery_panel(overrides \\ []) do
    assigns =
      Keyword.merge(
        [
          scan_errors: @scan_errors,
          scan_retrying: %{},
          scan_recovery_open: false,
          locale: "de",
          locale_version: 0
        ],
        overrides
      )

    render_component(&DeviceScanRecovery.recovery_panel/1, assigns)
  end

  test "renders recovery actions for validation failures" do
    html = render_recovery_panel()

    assert html =~ ~s/id="device-scan-recovery-panel"/
    assert html =~ "2 Objekte konnten nicht gelesen werden"
    assert html =~ "multistate_value:1"
    assert html =~ ~s/id="device-scan-recovery-value-1"/
    assert html =~ ~s/id="device-scan-recovery-ignore-invalid-1"/
    assert html =~ ~s/id="device-scan-recovery-all-1"/
    assert html =~ ~s/phx-value-skip-mode="value"/
    assert html =~ ~s/phx-value-skip-mode="ignore-invalid"/
    assert html =~ ~s/phx-value-skip-mode="all"/
    refute html =~ ~s/id="device-scan-recovery-value-2"/
    assert html =~ ~s/id="device-scan-recovery-ignore-invalid-2"/
    assert html =~ ~s/id="device-scan-recovery-all-2"/
  end

  test "is collapsed by default and preserves open state via assign" do
    collapsed = render_recovery_panel()
    refute collapsed =~ ~s(<details open)

    expanded =
      render_recovery_panel(scan_recovery_open: true)

    assert expanded =~ ~s/id="device-scan-recovery-panel" open/
    assert expanded =~ ~s/phx-click="toggle_scan_recovery_panel"/
  end

  test "renders bulk retry actions when applicable" do
    html = render_recovery_panel()

    assert html =~ ~s/id="device-scan-recovery-bulk-value"/
    assert html =~ ~s/id="device-scan-recovery-bulk-ignore-invalid"/
    assert html =~ ~s/id="device-scan-recovery-bulk-all"/
    assert html =~ ~s/id="device-scan-recovery-bulk-maximal"/
    assert html =~ ~s/phx-click="retry_all_scan_objects"/
    assert html =~ "Alle: Wertvalidierung überspringen"
    assert html =~ "Alle: Ungültige Eigenschaften auslassen"
    assert html =~ "Alle: Validierung überspringen"
    assert html =~ "Alle: Maximal nachlesen"
  end

  test "hides value bulk action when no objects support it" do
    html =
      render_recovery_panel(
        scan_errors: [
          %{
            object: "analog_input:2",
            object_id: %ObjectIdentifier{type: :analog_input, instance: 2},
            message: "Eigenschaftswert hat einen ungültigen BACnet-Datentyp (present value).",
            retry_modes: [true]
          }
        ]
      )

    refute html =~ ~s/id="device-scan-recovery-bulk-value"/
    refute html =~ ~s/id="device-scan-recovery-bulk-ignore-invalid"/
    assert html =~ ~s/id="device-scan-recovery-bulk-all"/
  end

  test "does not render when there are no scan errors" do
    html = render_recovery_panel(scan_errors: [])

    refute html =~ ~s/id="device-scan-recovery-panel"/
  end

  test "offers ignore-invalid recovery for cast/decode failures" do
    html =
      render_recovery_panel(
        scan_errors: [
          %{
            object: "network_port:3",
            object_id: %ObjectIdentifier{type: :network_port, instance: 3},
            reason: {:invalid_property_value, {:network_type, 68}},
            recoverable: true,
            retry_modes: [:ignore_invalid, :skip_all_and_ignore_invalid]
          },
          %{
            object: "network_port:1",
            object_id: %ObjectIdentifier{type: :network_port, instance: 1},
            reason: {:missing_optional_property, :bacnet_ip_mode},
            recoverable: false,
            retry_modes: []
          }
        ],
        scan_recovery_open: true
      )

    assert html =~ ~s/id="device-scan-recovery-panel"/
    assert html =~ "network_port:3"
    assert html =~ "network_port:1"
    assert html =~ "Einige Objekte haben ungültige BACnet-Werte"
    assert html =~ ~s/id="device-scan-recovery-ignore-invalid-1"/
    assert html =~ ~s/id="device-scan-recovery-maximal-1"/
    assert html =~ ~s/id="device-scan-recovery-bulk-ignore-invalid"/
    assert html =~ ~s/id="device-scan-recovery-bulk-maximal"/
    refute html =~ ~s/id="device-scan-recovery-value-1"/
    refute html =~ ~s/id="device-scan-recovery-all-1"/
    refute html =~ ~s/id="device-scan-recovery-bulk-value"/
    refute html =~ ~s/id="device-scan-recovery-bulk-all"/
    refute html =~ ~s/id="device-scan-recovery-ignore-invalid-2"/
  end

  test "lists non-recoverable failures without retry actions" do
    html =
      render_recovery_panel(
        scan_errors: [
          %{
            object: "network_port:1",
            object_id: %ObjectIdentifier{type: :network_port, instance: 1},
            reason: {:missing_optional_property, :bacnet_ip_mode},
            recoverable: false,
            retry_modes: []
          }
        ],
        scan_recovery_open: true
      )

    assert html =~ ~s/id="device-scan-recovery-panel"/
    assert html =~ "Diese Objekte konnten nicht gelesen werden"
    refute html =~ ~s/id="device-scan-recovery-ignore-invalid-1"/
    refute html =~ ~s/id="device-scan-recovery-bulk-ignore-invalid"/
  end

  test "renders scan error messages in english when locale is en" do
    html = render_recovery_panel(locale: "en", locale_version: 1)

    assert html =~ "objects could not be read"
    assert html =~ "BACnet specification"
    refute html =~ "Eigenschaftswert entspricht nicht"
  end

  test "shows retry status banner and disables actions while retrying" do
    html =
      render_recovery_panel(
        scan_retrying: %{"multistate_value:1" => true},
        scan_recovery_open: true
      )

    assert html =~ ~s/id="device-scan-recovery-status"/
    assert html =~ "Objekte werden mit reduzierter Validierung nachgelesen…"
    assert Regex.match?(~r/id="device-scan-recovery-bulk-value"[^>]*disabled/, html)
    assert Regex.match?(~r/id="device-scan-recovery-value-1"[^>]*disabled/, html)
    assert html =~ ~s/phx-disable-with="Wird nachgelesen…"/
    assert html =~ "animate-spin"
  end

  test "renders device load recovery panel for device-object failures" do
    html =
      render_component(&DeviceScanRecovery.device_load_recovery_panel/1, %{
        recovery: %{
          reason: {:invalid_property_value, {:tags, []}},
          retry_modes: [:ignore_invalid]
        },
        retrying?: false,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s/id="device-load-recovery-panel"/
    assert html =~ "Geräteobjekt konnte nicht gelesen werden"
    assert html =~ ~s/id="device-load-recovery-ignore-invalid"/
    assert html =~ ~s/phx-click="retry_device_load"/
    assert html =~ ~s/phx-value-skip-mode="ignore-invalid"/
    refute html =~ ~s/id="device-load-recovery-value"/
    refute html =~ ~s/id="device-load-recovery-all"/
  end

  test "device load recovery panel shows all offered modes" do
    html =
      render_component(&DeviceScanRecovery.device_load_recovery_panel/1, %{
        recovery: %{
          reason: {:value_failed_property_validation, :present_value},
          retry_modes: [:value, :ignore_invalid, true]
        },
        retrying?: false,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s/id="device-load-recovery-value"/
    assert html =~ ~s/id="device-load-recovery-ignore-invalid"/
    assert html =~ ~s/id="device-load-recovery-all"/
  end

  test "device load recovery panel is hidden without recovery or modes" do
    html =
      render_component(&DeviceScanRecovery.device_load_recovery_panel/1, %{
        recovery: nil,
        locale: "de",
        locale_version: 0
      })

    refute html =~ ~s/id="device-load-recovery-panel"/

    html_empty =
      render_component(&DeviceScanRecovery.device_load_recovery_panel/1, %{
        recovery: %{reason: :timeout, retry_modes: []},
        locale: "de",
        locale_version: 0
      })

    refute html_empty =~ ~s/id="device-load-recovery-panel"/
  end

  test "renders property load recovery panel" do
    html =
      render_component(&DeviceScanRecovery.property_load_recovery_panel/1, %{
        recovery: %{
          reason: {:invalid_property_value, {:tags, []}},
          retry_modes: [:ignore_invalid, :skip_all_and_ignore_invalid]
        },
        retrying?: false,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s/id="property-load-recovery-panel"/
    assert html =~ "Eigenschaften konnten nicht gelesen werden"
    assert html =~ ~s/id="property-load-recovery-ignore-invalid"/
    assert html =~ ~s/id="property-load-recovery-maximal"/
    assert html =~ ~s/phx-click="retry_property_load"/
  end
end
