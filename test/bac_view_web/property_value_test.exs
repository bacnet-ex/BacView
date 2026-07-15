defmodule BacViewWeb.PropertyValueTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.PropertyValue

  test "renders arrays collapsed by default with entry count" do
    display = %{
      kind: :array,
      formatted: "a, b",
      fields: [],
      items: [
        %{
          key: 1,
          label: "[1]",
          kind: :array_item,
          formatted: "scalar",
          fields: [],
          items: []
        },
        %{
          key: 2,
          label: "[2]",
          kind: :array_item,
          formatted: "more",
          fields: [],
          items: []
        }
      ]
    }

    html =
      render_component(&PropertyValue.property_value/1, %{
        display: display,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(<details)
    assert html =~ "2 Einträge"
    refute html =~ ~s(<details open)
    assert html =~ "[1]"
    assert html =~ "scalar"
  end

  test "renders nested array items as individually collapsible summaries" do
    display = %{
      kind: :array,
      formatted: "long",
      fields: [],
      items: [
        %{
          key: 1,
          label: "[1]",
          kind: :array_item,
          formatted: "Recipient: 1, Process Id: 2",
          fields: [
            %{
              key: :recipient,
              label: "Recipient",
              kind: :scalar,
              formatted: "1",
              fields: []
            },
            %{
              key: :process_id,
              label: "Process Id",
              kind: :scalar,
              formatted: "2",
              fields: []
            }
          ],
          items: []
        }
      ]
    }

    html =
      render_component(&PropertyValue.property_value/1, %{
        display: display,
        locale: "de",
        locale_version: 0
      })

    assert html =~ "1 Einträge"
    assert html =~ "[1] 2 Felder"
    assert html =~ ~s(id="bac-collapsible-row--array-item-1")
  end

  test "renders structs collapsed by default with field count" do
    display = %{
      kind: :struct,
      formatted: "To Offnormal: -, To Fault: -",
      fields: [
        %{
          key: :to_offnormal,
          label: "To Offnormal",
          kind: :scalar,
          formatted: "27.06.2026 14:30:00",
          fields: []
        },
        %{
          key: :to_fault,
          label: "To Fault",
          kind: :scalar,
          formatted: "-",
          fields: []
        },
        %{
          key: :to_normal,
          label: "To Normal",
          kind: :scalar,
          formatted: "-",
          fields: []
        }
      ],
      items: []
    }

    html =
      render_component(&PropertyValue.property_value/1, %{
        display: display,
        property: :event_timestamps,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(id="bac-collapsible-row-event_timestamps-struct")
    assert html =~ "3 Felder"
    refute html =~ ~s(<details open)
    assert html =~ "To Offnormal"
    assert html =~ "27.06.2026 14:30:00"
  end

  test "renders long scalar values collapsed with truncated summary" do
    long_value = String.duplicate("A", 80)

    display = %{
      kind: :scalar,
      formatted: long_value,
      fields: [],
      items: []
    }

    html =
      render_component(&PropertyValue.property_value/1, %{
        display: display,
        property: :description,
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(<details)
    assert html =~ String.slice(long_value, 0, 60) <> "…"
    refute html =~ ~s(<details open)
    assert html =~ long_value
  end
end
