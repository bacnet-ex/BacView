defmodule BacViewWeb.ObjectDetailTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.StatusFlags
  alias BacViewWeb.ObjectDetail

  test "renders status flags in header when property exists" do
    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      status_flags: %StatusFlags{
        in_alarm: false,
        fault: true,
        overridden: false,
        out_of_service: false
      },
      present_value: 21.0,
      present_value_formatted: "21.0",
      writable: false,
      commandable: false,
      units: nil,
      updated_at: nil
    }

    properties = [
      %{
        property: :status_flags,
        property_name: "Status Flags",
        type: "Status Flags",
        value: object.status_flags,
        value_display: %{kind: :scalar, formatted: "—", fields: [], items: []},
        value_formatted: "—",
        writable: false
      }
    ]

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: properties,
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "Störung (aktiv)"
    assert html =~ "In Alarm (inaktiv)"
  end

  test "renders writable property write actions without locale error" do
    prop = %{
      type: "REAL",
      value: 1.0,
      property: :cov_increment,
      writable: true,
      property_name: "cov increment",
      value_display: %{kind: :scalar, formatted: "1", fields: [], items: []},
      value_formatted: "1",
      bac_type: :real
    }

    object = %{
      name: "Test Object",
      type: :analog_input,
      instance: 1,
      writable: false,
      present_value: 5.0,
      present_value_formatted: "5",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    device = %{id: 1}

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: device,
          object: object,
          properties: [prop],
          locale: "de",
          locale_version: 0,
          write_priority: 8,
          writing_property: nil
        }
      )

    assert html =~ "Schreiben"
    assert html =~ "cov increment"
  end

  test "renders writable enumerations as dropdowns even after property row sanitization" do
    prop =
      BacView.Text.sanitize_property_row(%{
        type: "ENUMERATED",
        value: :normal,
        property: :event_state,
        writable: true,
        property_name: "event state",
        bac_type: {:constant, :event_state},
        enum_type: :event_state,
        enum_options: BacView.BACnet.Protocol.PropertyEnumeration.options(:event_state),
        value_display: %{kind: :scalar, formatted: "normal", fields: [], items: []},
        value_formatted: "normal"
      })

    html = render_writable_property(prop)

    assert html =~ ~s(<select)
    assert html =~ "normal"
    refute html =~ ~s(phx-click="open_write_property_modal")
  end

  test "renders writable booleans as checkboxes even after property row sanitization" do
    prop =
      BacView.Text.sanitize_property_row(%{
        type: "BOOLEAN",
        value: true,
        property: :out_of_service,
        writable: true,
        property_name: "out of service",
        bac_type: :boolean,
        value_display: %{kind: :scalar, formatted: "true", fields: [], items: []},
        value_formatted: "true"
      })

    html = render_writable_property(prop)

    assert html =~ ~s(type="checkbox")
    assert html =~ "Aktiv"
    refute html =~ ~s(phx-click="open_write_property_modal")
  end

  test "property value collapsible ids differ between row and modal contexts" do
    display = %{
      kind: :struct,
      formatted: "Object Identifier: binary_value:189, Property: present_value",
      fields: [
        %{
          key: :object_identifier,
          label: "Object Identifier",
          kind: :object_identifier,
          value: %BACnet.Protocol.ObjectIdentifier{type: :binary_value, instance: 189},
          formatted: "binary_value:189",
          fields: []
        }
      ],
      items: []
    }

    row_html =
      render_component(
        &BacViewWeb.PropertyValue.property_value/1,
        %{display: display, property: :event_algorithm_inhibit_ref, dom_id_prefix: "row"}
      )

    modal_html =
      render_component(
        &BacViewWeb.PropertyValue.property_value/1,
        %{display: display, property: :event_algorithm_inhibit_ref, dom_id_prefix: "modal"}
      )

    assert row_html =~ "bac-collapsible-row-event_algorithm_inhibit_ref-struct"
    assert modal_html =~ "bac-collapsible-modal-event_algorithm_inhibit_ref-struct"
    refute row_html =~ "bac-collapsible-modal-"
  end

  test "renders complex writable properties with formatted value instead of empty input" do
    prop = %{
      type: "STRUCT",
      value: %BACnet.Protocol.BACnetDateTime{
        date: %BACnet.Protocol.BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
        time: %BACnet.Protocol.BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 13}
      },
      property: :change_of_state_time,
      writable: true,
      property_name: "change of state time",
      value_display: %{
        kind: :scalar,
        formatted: "27.06.2026 17:17:43.130",
        fields: [],
        items: []
      },
      value_formatted: "27.06.2026 17:17:43.130",
      bac_type: {:struct, BACnet.Protocol.BACnetDateTime}
    }

    object = %{
      name: "BV-1",
      type: :binary_value,
      instance: 189,
      writable: false,
      present_value: true,
      present_value_formatted: "true",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [prop],
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "change of state time"
    assert html =~ "27.06.2026 17:17:43.130"
    assert html =~ "Bearbeiten"
    refute html =~ ~s(id="write-form-change_of_state_time")
  end

  test "renders hero icon for binary_value objects" do
    object = %{
      name: "BV-1",
      type: :binary_value,
      instance: 1,
      writable: false,
      present_value: true,
      present_value_formatted: "true",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "bac-object-hero-icon"
    assert html =~ "<svg"
    assert html =~ "<path"
  end

  test "renders properties refresh button" do
    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      writable: false,
      present_value: 1.0,
      present_value_formatted: "1.0",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(id="refresh-properties-btn")
    assert html =~ ~s(phx-click="refresh_properties")
    refute html =~ ~s(id="refresh-properties-btn" disabled)
  end

  test "renders prominent reading status while refreshing properties" do
    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      writable: false,
      present_value: 1.0,
      present_value_formatted: "1.0",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    properties = [
      %{
        property: :present_value,
        property_name: "present value",
        type: "REAL",
        value: 1.0,
        value_display: %{kind: :scalar, formatted: "1.0", fields: [], items: []},
        value_formatted: "1.0",
        writable: false
      }
    ]

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: properties,
          properties_loading: true,
          properties_reading_visible: true,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(id="object-reading-status")
    assert html =~ "Eigenschaften werden gelesen…"
    assert html =~ "bac-reading-bar"
    assert html =~ "bac-table-reading"
    assert html =~ ~s(aria-busy="true")
  end

  test "disables properties refresh button while loading" do
    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      writable: false,
      present_value: 1.0,
      present_value_formatted: "1.0",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          properties_loading: true,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(id="refresh-properties-btn")
    assert html =~ ~s(<button type="button" id="refresh-properties-btn")
    assert html =~ "disabled"
    assert html =~ "animate-spin"
  end

  test "renders chart button on log buffer without cov or write actions" do
    object = %{
      name: "Trend 1",
      type: :trend_log,
      instance: 1,
      present_value: nil,
      present_value_formatted: "—",
      writable: false,
      commandable: false,
      units: nil,
      updated_at: nil
    }

    log_buffer = %{
      property: :log_buffer,
      property_name: "Log Buffer",
      type: "BACnetLOGRECORD",
      value: nil,
      value_display: %{kind: :scalar, formatted: "—", fields: [], items: []},
      value_formatted: "—",
      writable: true
    }

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [log_buffer],
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "trend-chart-open"
    assert html =~ "Diagramm"
    refute html =~ "write-form-log_buffer"
    refute html =~ "phx-value-property=\"log_buffer\""
    refute html =~ "trend-log-chart-modal"
  end

  defp render_writable_property(prop) do
    object = %{
      name: "Test Object",
      type: :analog_input,
      instance: 1,
      writable: false,
      present_value: 5.0,
      present_value_formatted: "5",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    render_component(
      &ObjectDetail.object_detail/1,
      %{
        device: %{id: 1},
        object: object,
        properties: [prop],
        locale: "de",
        locale_version: 0,
        write_priority: 8,
        writing_property: nil
      }
    )
  end
end
