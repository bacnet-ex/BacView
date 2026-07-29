defmodule BacViewWeb.WritePropertyModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.{BACnetArray, DeviceObjectPropertyRef, ObjectIdentifier}
  alias BacView.BACnet.Protocol.ComplexPropertyEditor
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
          value: 1.0,
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
          value: 1.0,
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

  test "shows add entry button for empty list_of_object_property_references array" do
    array = BACnetArray.new()

    html =
      render_component(&WritePropertyModal.modal/1, %{
        object: %{type: :schedule, instance: 1, name: "Schedule"},
        property: %{
          property: :list_of_object_property_references,
          property_name: "List Of Object Property References",
          value: array,
          value_display: %{kind: :list, formatted: "[]", fields: [], items: []}
        },
        editor_mode: :fields,
        form_fields: [],
        draft_fields: %{},
        draft_value: array,
        draft_json: "[]",
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(id="write-property-add-item")
    assert html =~ "Eintrag hinzufügen"
    assert html =~ "Keine Einträge"
    # Empty collections are valid writes (e.g. clear all object refs)
    refute html =~ ~s(id="write-property-submit" disabled)
  end

  test "groups collection fields with remove buttons" do
    ref = %DeviceObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :analog_value, instance: 1},
      property_identifier: :present_value,
      property_array_index: nil,
      device_identifier: nil
    }

    array = BACnetArray.from_list([ref], false)
    form_fields = ComplexPropertyEditor.form_fields(array)

    html =
      render_component(&WritePropertyModal.modal/1, %{
        object: %{type: :schedule, instance: 1, name: "Schedule"},
        property: %{
          property: :list_of_object_property_references,
          property_name: "List Of Object Property References",
          value: array,
          value_display: %{kind: :list, formatted: "[1]", fields: [], items: []}
        },
        editor_mode: :fields,
        form_fields: form_fields,
        draft_fields: ComplexPropertyEditor.initial_field_params(form_fields),
        draft_value: array,
        draft_json: "[]",
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s(id="write-property-item-0")
    assert html =~ ~s(id="write-property-remove-item-0")
    assert html =~ ~s(id="write-property-add-item")
  end

  test "field labels expose full text via title tooltip" do
    form_fields = [
      %{
        path: "0.object_identifier.type",
        label: "[1] · Object Identifier · Type",
        value: "analog_value",
        readonly: false,
        enum_options: [%{value: :analog_value, label: "analog_value"}]
      }
    ]

    html =
      render_component(&WritePropertyModal.modal/1, %{
        object: %{type: :schedule, instance: 1, name: "Schedule"},
        property: %{
          property: :list_of_object_property_references,
          property_name: "List Of Object Property References",
          value: [],
          value_display: %{kind: :list, formatted: "[]", fields: [], items: []}
        },
        editor_mode: :fields,
        form_fields: form_fields,
        draft_fields: %{"0.object_identifier.type" => "analog_value"},
        draft_value: [],
        draft_json: "[]",
        locale: "de",
        locale_version: 0
      })

    assert html =~ ~s|title="[1] · Object Identifier · Type (0.object_identifier.type)"|
    assert html =~ ~s|class="sm:w-2/5 shrink-0 text-xs bac-mono bac-text-faint truncate"|
  end
end
