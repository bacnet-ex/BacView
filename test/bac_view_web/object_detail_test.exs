defmodule BacViewWeb.ObjectDetailTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacViewWeb.ObjectDetail

  test "shows struct name tooltip on STRUCT type column" do
    flags = %StatusFlags{
      in_alarm: false,
      fault: true,
      overridden: false,
      out_of_service: false
    }

    display = PropertyDisplay.build(flags)

    prop = %{
      property: :status_flags,
      property_name: "status flags",
      type: "STRUCT",
      value: flags,
      value_display: display,
      value_formatted: display.formatted,
      writable: false
    }

    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      status_flags: flags,
      writable: false,
      present_value: 21.0,
      present_value_formatted: "21.0",
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

    assert html =~ ~s(title="BACnet.Protocol.StatusFlags")
    assert html =~ "STRUCT"
  end

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
        value_display: %{kind: :scalar, formatted: "-", fields: [], items: []},
        value_formatted: "-",
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

  test "renders status flags in header from object._unknown_properties" do
    flags = %StatusFlags{
      in_alarm: false,
      fault: true,
      overridden: false,
      out_of_service: false
    }

    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      status_flags: nil,
      _unknown_properties: %{status_flags: flags},
      present_value: 21.0,
      present_value_formatted: "21.0",
      writable: false,
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
          unknown_properties: [],
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "Störung (aktiv)"
    assert html =~ "In Alarm (inaktiv)"
  end

  test "renders status flags in header from unknown_properties rows" do
    flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: false,
      out_of_service: false
    }

    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      status_flags: nil,
      present_value: 21.0,
      present_value_formatted: "21.0",
      writable: false,
      commandable: false,
      units: nil,
      updated_at: nil
    }

    unknown_properties = [
      %{
        property: :status_flags,
        property_name: "Status Flags",
        type: "Status Flags",
        value: flags,
        value_display: %{kind: :scalar, formatted: "-", fields: [], items: []},
        value_formatted: "-",
        writable: false
      }
    ]

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          unknown_properties: unknown_properties,
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "In Alarm (aktiv)"
  end

  test "unknown properties section shows edit toggle and primitive write form when editing" do
    encoding = %Encoding{
      encoding: :primitive,
      type: :unsigned_integer,
      value: 41_160,
      extras: []
    }

    proprietary = [
      %Encoding{
        encoding: :primitive,
        type: :unsigned_integer,
        value: 1,
        extras: []
      },
      %Encoding{
        encoding: :primitive,
        type: :unsigned_integer,
        value: 2,
        extras: []
      }
    ]

    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      present_value: 21.0,
      present_value_formatted: "21.0",
      writable: false,
      commandable: false,
      units: nil,
      updated_at: nil
    }

    unknown_properties = [
      %{
        property: 512,
        property_name: "512",
        type: "UNSIGNED INTEGER",
        value: encoding,
        value_display: %{kind: :scalar, formatted: "41160", fields: [], items: []},
        value_formatted: "41160",
        string_value?: false,
        hex_toggle?: false,
        raw_binary: nil,
        primitive_editable?: true
      },
      %{
        property: 900,
        property_name: "900",
        type: "PROPRIETARY",
        value: proprietary,
        value_display: %{kind: :scalar, formatted: "01:02", fields: [], items: []},
        value_formatted: "01:02",
        string_value?: true,
        hex_toggle?: false,
        raw_binary: <<1, 2>>,
        primitive_editable?: false
      }
    ]

    readonly_html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          unknown_properties: unknown_properties,
          unknown_properties_editing: false,
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert readonly_html =~ ~s(id="toggle-unknown-properties-editing")
    assert readonly_html =~ "Bearbeiten"
    refute readonly_html =~ ~s(id="write-unknown-form-512")
    assert readonly_html =~ "41160"

    editing_html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          unknown_properties: unknown_properties,
          unknown_properties_editing: true,
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert editing_html =~ "Nur lesen"
    assert editing_html =~ ~s(id="write-unknown-form-512")
    assert editing_html =~ ~s(id="write-unknown-input-512")
    refute editing_html =~ ~s(id="write-unknown-form-900")
  end

  test "hides unknown-properties edit toggle when no primitive-editable rows exist" do
    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      present_value: 21.0,
      present_value_formatted: "21.0",
      writable: false,
      commandable: false,
      units: nil,
      updated_at: nil
    }

    unknown_properties = [
      %{
        property: 900,
        property_name: "900",
        type: "PROPRIETARY",
        value: [],
        value_display: %{kind: :scalar, formatted: "-", fields: [], items: []},
        value_formatted: "-",
        string_value?: true,
        hex_toggle?: false,
        raw_binary: <<>>,
        primitive_editable?: false
      }
    ]

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          unknown_properties: unknown_properties,
          unknown_properties_editing: true,
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    refute html =~ ~s(id="toggle-unknown-properties-editing")
    refute html =~ ~s(id="write-unknown-form-900")
  end

  test "renders status flags header tiles in English when locale is en" do
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
        value_display: %{kind: :scalar, formatted: "-", fields: [], items: []},
        value_formatted: "-",
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
          locale: "en",
          locale_version: 1
        }
      )

    assert html =~ "Fault (active)"
    assert html =~ "In alarm (inactive)"
    assert html =~ "Overridden (inactive)"
    assert html =~ "Out of service (inactive)"
    refute html =~ "Störung"
    refute html =~ "Übersteuert"
    refute html =~ "Ausser Betrieb"
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

  test "renders multistate present value with state text and dropdown options" do
    object = %{
      name: "MSV-1",
      type: :multi_state_value,
      instance: 1,
      writable: true,
      commandable: false,
      present_value: 2,
      present_value_formatted: "2 (On)",
      number_of_states: 2,
      state_text: ["Off", "On"],
      units: nil,
      updated_at: nil
    }

    prop =
      BacView.BACnet.Protocol.PropertyWriter.enrich_properties(
        [
          %{
            property: :present_value,
            property_name: "present value",
            type: "INTEGER",
            value: 2,
            writable: true,
            bac_type: :unsigned_integer,
            value_display: %{kind: :scalar, formatted: "2", fields: [], items: []},
            value_formatted: "2"
          }
        ],
        object
      )
      |> List.first()

    html =
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

    assert html =~ "2 (On)"
    assert html =~ ~s(<select)
    assert html =~ "1 (Off)"
    assert html =~ "2 (On)"
  end

  test "renders out-of-range multistate values in dropdown with synthetic current option" do
    object = %{
      name: "MSV-1",
      type: :multi_state_value,
      instance: 1,
      writable: true,
      commandable: false,
      present_value: 0,
      present_value_formatted: "0",
      number_of_states: 2,
      state_text: ["Off", "On"],
      units: nil,
      updated_at: nil
    }

    prop =
      BacView.BACnet.Protocol.PropertyWriter.enrich_properties(
        [
          %{
            property: :present_value,
            property_name: "present value",
            type: "INTEGER",
            value: 0,
            writable: true,
            bac_type: :unsigned_integer,
            value_display: %{kind: :scalar, formatted: "0", fields: [], items: []},
            value_formatted: "0"
          }
        ],
        object
      )
      |> List.first()

    html =
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

    assert html =~ ~s(id="write-enum-select-present_value")
    assert html =~ ~s(value="0")
    assert html =~ "1 (Off)"
    assert html =~ "2 (On)"
    assert html =~ ~s(id="prop-enum-free-toggle-present_value")
  end

  test "renders binary present_value with inactive/active text" do
    object = %{
      name: "BV-1",
      type: :binary_value,
      instance: 1,
      writable: true,
      commandable: false,
      present_value: true,
      present_value_formatted: "Open",
      inactive_text: "Closed",
      active_text: "Open",
      units: nil,
      updated_at: nil
    }

    prop =
      BacView.BACnet.Protocol.PropertyWriter.enrich_properties(
        [
          %{
            property: :present_value,
            property_name: "present value",
            type: "BOOLEAN",
            value: true,
            writable: true,
            bac_type: :boolean,
            value_display: %{kind: :scalar, formatted: "true", fields: [], items: []},
            value_formatted: "true"
          }
        ],
        object
      )
      |> List.first()

    html =
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

    assert html =~ "Open"
    assert prop.value_formatted == "Open"
  end

  test "renders multistate relinquish_default with state text and dropdown options" do
    object = %{
      name: "MSV-1",
      type: :multi_state_value,
      instance: 1,
      writable: false,
      commandable: true,
      present_value: 2,
      present_value_formatted: "2 (On)",
      number_of_states: 2,
      state_text: ["Off", "On"],
      units: nil,
      updated_at: nil
    }

    prop =
      BacView.BACnet.Protocol.PropertyWriter.enrich_properties(
        [
          %{
            property: :relinquish_default,
            property_name: "relinquish default",
            type: "INTEGER",
            value: 1,
            writable: true,
            bac_type: :unsigned_integer,
            value_display: %{kind: :scalar, formatted: "1", fields: [], items: []},
            value_formatted: "1"
          }
        ],
        object
      )
      |> List.first()

    html =
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

    assert html =~ "1 (Off)"
    assert html =~ ~s(<select)
    assert html =~ "1 (Off)"
    assert html =~ "2 (On)"
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

  test "renders writable in_list properties as dropdowns" do
    bac_type =
      {:in_list, [:confirmed_cov_if_possible, :polling, :unconfirmed_cov_if_possible]}

    prop =
      BacView.Text.sanitize_property_row(%{
        type: "ENUMERATED",
        value: :polling,
        property: :subscription_type,
        writable: true,
        property_name: "subscription type",
        bac_type: bac_type,
        enum_options:
          BacView.BACnet.Protocol.PropertyEnumeration.in_list_options(elem(bac_type, 1)),
        value_display: %{kind: :scalar, formatted: "polling", fields: [], items: []},
        value_formatted: "polling"
      })

    html = render_writable_property(prop)

    assert html =~ ~s(<select)
    assert html =~ "polling"
    assert html =~ "confirmed cov if possible"
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
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(id="object-refresh-banner")
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

  test "renders single trend log jump button next to cov controls" do
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
          locale_version: 0,
          object_nav_targets: [
            %{
              type: :trend_log,
              instance: 2,
              name: "Trend 2",
              label: "Trend 2 (trend_log:2)",
              href: "/devices/1/objects/trend_log/2"
            }
          ]
        }
      )

    assert html =~ ~s(id="object-nav-jump")
    assert html =~ "Zum Trendprotokoll"
    refute html =~ ~s(id="object-nav-menu-toggle")
    refute html =~ ~s(id="trend-chart-open-header")
  end

  test "renders referenced object dropdown for trend log multiple targets" do
    object = %{
      name: "Trend 5",
      type: :trend_log_multiple,
      instance: 5,
      present_value: nil,
      present_value_formatted: "-",
      writable: false,
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
          locale_version: 0,
          object_nav_targets: [
            %{
              type: :analog_input,
              instance: 1,
              name: "AI-1",
              label: "AI-1 (analog_input:1)",
              href: "/devices/1/objects/analog_input/1"
            },
            %{
              type: :binary_input,
              instance: 2,
              name: "BI-2",
              label: "BI-2 (binary_input:2)",
              href: "/devices/1/objects/binary_input/2"
            }
          ],
          object_nav_menu_open: true
        }
      )

    assert html =~ ~s(id="object-nav-menu-toggle")
    assert html =~ "Referenzierte Objekte"
    assert html =~ ~s(id="object-nav-menu")
    assert html =~ "AI-1 (analog_input:1)"
    assert html =~ "BI-2 (binary_input:2)"
    refute html =~ ~s(id="object-nav-jump")
    assert html =~ ~s(id="trend-chart-open-header")
    assert html =~ "phx-click=\"open_trend_chart_modal\""
  end

  test "renders chart button on log buffer without cov or write actions" do
    object = %{
      name: "Trend 1",
      type: :trend_log,
      instance: 1,
      present_value: nil,
      present_value_formatted: "-",
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
      value_display: %{kind: :scalar, formatted: "-", fields: [], items: []},
      value_formatted: "-",
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
    assert html =~ ~s(id="trend-chart-open-header")
    assert html =~ "Diagramm"
    assert html =~ ~s(id="prop-log_buffer")
    # Value column is always blank ("-"); chart uses ReadRange, not this cell.
    assert html =~ ~r/id="prop-log_buffer"[\s\S]*?>\s*-\s*</
    refute html =~ "write-form-log_buffer"
    refute html =~ "phx-value-property=\"log_buffer\""
    refute html =~ "trend-log-chart-modal"
  end

  test "renders unknown properties in a separate readonly table" do
    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      writable: false,
      present_value: 21.0,
      present_value_formatted: "21.0",
      commandable: false,
      units: nil,
      updated_at: nil
    }

    integer_encoding = %BACnet.Protocol.ApplicationTags.Encoding{
      encoding: :primitive,
      type: :unsigned_integer,
      value: 42,
      extras: []
    }

    string_encoding = %BACnet.Protocol.ApplicationTags.Encoding{
      encoding: :primitive,
      type: :character_string,
      value: "x",
      extras: []
    }

    binary_encoding = %BACnet.Protocol.ApplicationTags.Encoding{
      encoding: :primitive,
      type: :character_string,
      value: "a\0b",
      extras: []
    }

    unknown_properties = [
      %{
        property: 512,
        property_name: "property 512",
        type: "UNSIGNED INTEGER",
        value: integer_encoding,
        value_display: PropertyDisplay.build(42),
        value_formatted: "42",
        string_value?: false,
        raw_binary: nil
      },
      %{
        property: :vendor_prop,
        property_name: "vendor prop",
        type: "CHARACTER STRING",
        value: string_encoding,
        value_display: PropertyDisplay.build(string_encoding),
        value_formatted: "x",
        string_value?: true,
        hex_toggle?: false,
        raw_binary: "x"
      },
      %{
        property: :binary_prop,
        property_name: "binary prop",
        type: "CHARACTER STRING",
        value: binary_encoding,
        value_display: PropertyDisplay.build("a\0b"),
        value_formatted: "a\0b",
        string_value?: true,
        hex_toggle?: false,
        raw_binary: "a\0b"
      }
    ]

    html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [],
          unknown_properties: unknown_properties,
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(id="object-unknown-properties-panel")
    assert html =~ ~s(id="object-detail-unknown-properties-table")
    assert html =~ "Unbekannte Eigenschaften"
    assert html =~ "3 unbekannte Eigenschaften"
    assert html =~ "property 512"
    assert html =~ "vendor prop"
    refute html =~ ~s(id="object-detail-properties-table")
    assert html =~ ~s(phx-click="sort_unknown_properties")
    assert html =~ ~s(id="unknown-property-sort-name")
    refute html =~ ~s(id="unknown-prop-hex-toggle-vendor_prop")
    refute html =~ ~s(id="unknown-prop-hex-toggle-binary_prop")
    refute html =~ ~s(id="unknown-prop-hex-toggle-512")

    unknown_section =
      html
      |> String.split(~s(id="object-unknown-properties-panel"), parts: 2)
      |> Enum.at(1, "")

    refute unknown_section =~ "Aktionen"
    refute unknown_section =~ "write-form-"
    refute unknown_section =~ "subscribe_cov"
  end

  test "read-only printable octet string toggles between text and hex" do
    raw = "ABCD"

    prop = %{
      property: :present_value,
      property_name: "present value",
      type: "OCTET STRING",
      bac_type: :octet_string,
      value: raw,
      value_display: %{kind: :scalar, formatted: "ABCD", fields: [], items: []},
      value_formatted: "ABCD",
      string_value?: true,
      hex_toggle?: true,
      raw_binary: raw,
      writable: false
    }

    object = %{
      name: "OSV-1",
      type: :octet_string_value,
      instance: 1,
      status_flags: nil,
      present_value: raw,
      present_value_formatted: "ABCD",
      writable: false,
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
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "ABCD"
    assert html =~ ~s(id="prop-hex-toggle-present_value")
    assert html =~ "Als Hex"
    refute html =~ "41:42:43:44"

    hex_html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [prop],
          property_hex_keys: MapSet.new([:present_value]),
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert hex_html =~ "41:42:43:44"
    assert hex_html =~ "Als Text"
  end

  test "does not show hex toggle for character-string properties" do
    raw = "a\0b"

    prop = %{
      property: :description,
      property_name: "description",
      type: "CHARACTER STRING",
      bac_type: :string,
      value: raw,
      value_display: %{kind: :scalar, formatted: raw, fields: [], items: []},
      value_formatted: raw,
      string_value?: true,
      hex_toggle?: false,
      raw_binary: raw,
      writable: false
    }

    object = %{
      name: "AI-1",
      type: :analog_input,
      instance: 1,
      status_flags: nil,
      present_value: 21.0,
      present_value_formatted: "21.0",
      writable: false,
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
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    refute html =~ ~s(id="prop-hex-toggle-description")
  end

  test "shows hex toggle on writable printable octet-string properties" do
    raw = "ABCD"

    prop = %{
      property: :present_value,
      property_name: "present value",
      type: "OCTET STRING",
      bac_type: :octet_string,
      value: raw,
      value_display: %{
        kind: :scalar,
        formatted: "ABCD",
        fields: [],
        items: []
      },
      value_formatted: "ABCD",
      string_value?: true,
      hex_toggle?: true,
      raw_binary: raw,
      writable: true
    }

    object = %{
      name: "OSV-1",
      type: :octet_string_value,
      instance: 1,
      status_flags: nil,
      present_value: raw,
      present_value_formatted: "ABCD",
      writable: true,
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
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(id="write-form-present_value")
    assert html =~ ~s(id="write-input-present_value")
    assert html =~ ~s(id="prop-hex-toggle-present_value")
    assert html =~ "Als Hex"
    # Text mode (default): raw printable bytes in the input
    assert html =~ ~s(value="ABCD")
    # Printable octets do not force encoding=hex
    refute html =~ ~s(name="encoding")

    hex_html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [prop],
          property_hex_keys: MapSet.new([:present_value]),
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert hex_html =~ ~s(value="41:42:43:44")
    assert hex_html =~ "Als Text"
    assert hex_html =~ ~s(name="encoding")
    assert hex_html =~ ~s(value="hex")
  end

  test "writable opaque mac_address is hex-only with no text/hex toggle" do
    mac = <<10, 130, 3, 51, 186, 192>>

    prop = %{
      property: :mac_address,
      property_name: "mac address",
      type: "OCTET STRING",
      bac_type: :octet_string,
      value: mac,
      value_display: %{
        kind: :scalar,
        formatted: "10.130.3.51:47808",
        fields: [],
        items: []
      },
      value_formatted: "10.130.3.51:47808",
      string_value?: true,
      hex_toggle?: true,
      raw_binary: mac,
      writable: true
    }

    object = %{
      name: "NP-1",
      type: :network_port,
      instance: 1,
      status_flags: nil,
      present_value: nil,
      present_value_formatted: "-",
      writable: true,
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
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    # Write field is colon-hex; toggle is hidden because text/hex modes are identical.
    assert html =~ ~s(id="write-form-mac_address")
    assert html =~ ~s(value="0A:82:03:33:BA:C0")
    refute html =~ "0A:C2:82"
    assert html =~ ~s(name="encoding")
    refute html =~ ~s(id="prop-hex-toggle-mac_address")
    refute html =~ ~s(id="prop-display-mac_address")
  end

  test "writable opaque octet already in hex hides the no-op hex toggle" do
    raw = <<0x00, 0x30, 0xDE, 0x52, 0x55, 0xCA>>

    prop = %{
      property: :present_value,
      property_name: "present value",
      type: "OCTET STRING",
      bac_type: :octet_string,
      value: raw,
      value_display: %{
        kind: :scalar,
        formatted: "00:30:DE:52:55:CA",
        fields: [],
        items: []
      },
      value_formatted: "00:30:DE:52:55:CA",
      string_value?: true,
      hex_toggle?: false,
      raw_binary: raw,
      writable: true
    }

    object = %{
      name: "OSV-1",
      type: :octet_string_value,
      instance: 1,
      status_flags: nil,
      present_value: raw,
      present_value_formatted: "00:30:DE:52:55:CA",
      writable: true,
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
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ ~s(value="00:30:DE:52:55:CA")
    refute html =~ ~s(id="prop-hex-toggle-present_value")
  end

  test "read-only mac_address shows MAC-aware formatting and correct hex toggle" do
    mac = <<10, 130, 3, 51, 186, 192>>

    prop = %{
      property: :mac_address,
      property_name: "mac address",
      type: "OCTET STRING",
      bac_type: :octet_string,
      value: mac,
      value_display: %{
        kind: :scalar,
        formatted: "10.130.3.51:47808",
        fields: [],
        items: []
      },
      value_formatted: "10.130.3.51:47808",
      string_value?: true,
      hex_toggle?: true,
      raw_binary: mac,
      writable: false
    }

    object = %{
      name: "NP-1",
      type: :network_port,
      instance: 1,
      status_flags: nil,
      present_value: nil,
      present_value_formatted: "-",
      writable: false,
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
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "10.130.3.51:47808"
    assert html =~ ~s(id="prop-hex-toggle-mac_address")
    assert html =~ "Als Hex"

    hex_html =
      render_component(
        &ObjectDetail.object_detail/1,
        %{
          device: %{id: 1},
          object: object,
          properties: [prop],
          property_hex_keys: MapSet.new([:mac_address]),
          properties_loading: false,
          locale: "de",
          locale_version: 0
        }
      )

    assert hex_html =~ "0A:82:03:33:BA:C0"
    refute hex_html =~ "0A:C2:82"
    assert hex_html =~ "Als Text"
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
