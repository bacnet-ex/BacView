defmodule BacViewWeb.WritePropertyModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.WritePropertyModal

  defp encoding_fields do
    [
      %{
        path: "encoding",
        label: "Encoding",
        value: "primitive",
        readonly: false,
        enum_options: [%{value: :primitive, label: "PRIMITIVE"}]
      },
      %{
        path: "extras.tag_number",
        label: "Extras · Tag Number",
        value: "",
        readonly: false,
        enum_options: nil
      }
    ]
  end

  test "disables tag number input when encoding is primitive" do
    html =
      render_component(&WritePropertyModal.modal/1, %{
        object: %{type: :schedule, instance: 1, name: "Schedule"},
        property: %{
          property: :present_value,
          property_name: "Present Value",
          value_display: %{kind: :scalar, formatted: "REAL: 1", fields: [], items: []}
        },
        editor_mode: :fields,
        form_fields: encoding_fields(),
        draft_fields: %{"encoding" => "primitive"},
        draft_json: "{}",
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(id="write-field-extras-tag_number")
    assert html =~ ~s(disabled)
    assert html =~ ~s(name="field[extras.tag_number]")
  end

  test "enables tag number input for tagged encoding" do
    html =
      render_component(&WritePropertyModal.modal/1, %{
        object: %{type: :schedule, instance: 1, name: "Schedule"},
        property: %{
          property: :present_value,
          property_name: "Present Value",
          value_display: %{kind: :scalar, formatted: "REAL: 1", fields: [], items: []}
        },
        editor_mode: :fields,
        form_fields: encoding_fields(),
        draft_fields: %{"encoding" => "tagged"},
        draft_json: "{}",
        locale: "de",
        locale_version: 0
      })

    refute html =~
             ~s(name="field[extras.tag_number]" type="text" value="" class="flex-1 bac-input bac-input-sm bac-mono text-xs" disabled)
  end
end
