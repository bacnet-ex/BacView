defmodule BacView.BACnet.Protocol.PropertyEnumerationTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectTypes.AnalogInput
  alias BacView.BACnet.Protocol.PropertyEnumeration

  describe "options/1" do
    test "lists event_state values from Constants" do
      options = PropertyEnumeration.options(:event_state)

      assert Enum.any?(options, &(&1.value == :normal))
      assert Enum.any?(options, &(&1.value == :fault))
      assert Enum.all?(options, &is_binary(&1.label))
    end

    test "includes integer values in dropdown labels" do
      options = PropertyEnumeration.options(:reliability)

      assert Enum.find(options, &(&1.value == :no_fault_detected)).label ==
               "no fault detected (0)"

      assert Enum.find(options, &(&1.value == :configuration_error)).label ==
               "configuration error (10)"
    end
  end

  describe "enrich_property/2" do
    test "attaches enum metadata for constant property types" do
      prop = %{
        property: :event_state,
        value: :normal,
        value_display: %{kind: :scalar, formatted: "normal"},
        value_formatted: "normal",
        type: "ENUMERATED"
      }

      enriched = PropertyEnumeration.enrich_property(prop, {:constant, :event_state})

      assert enriched.enum_type == :event_state
      assert enriched.type == "ENUMERATED"
      assert length(enriched.enum_options) > 0
      assert enriched.value_formatted == "Normal"
    end

    test "leaves non-constant properties without enum metadata" do
      prop = %{property: :present_value, type: "REAL"}

      enriched = PropertyEnumeration.enrich_property(prop, :real)

      assert enriched.property == :present_value
      assert enriched.type == "REAL"
      refute Map.has_key?(enriched, :enum_type)
      assert enriched.enum_options == nil
    end
  end

  describe "dropdown?/1" do
    test "uses dropdown when value matches an enum option" do
      prop = %{
        value: :normal,
        enum_options: PropertyEnumeration.options(:event_state)
      }

      assert PropertyEnumeration.dropdown?(prop)
    end

    test "falls back to text input when integer value is not in enum options" do
      prop = %{
        value: 99,
        enum_options: PropertyEnumeration.options(:event_state)
      }

      refute PropertyEnumeration.dropdown?(prop)
    end

    test "uses dropdown when value is nil" do
      prop = %{
        value: nil,
        enum_options: [%{value: 1, label: "1"}]
      }

      assert PropertyEnumeration.dropdown?(prop)
    end
  end

  describe "parse_value/2" do
    test "accepts valid enum atoms" do
      assert PropertyEnumeration.parse_value("normal", :event_state) == {:ok, :normal}
    end

    test "rejects unknown enum values" do
      assert PropertyEnumeration.parse_value("not_a_state", :event_state) ==
               {:error, :invalid_enum}
    end
  end

  describe "integration with object type map" do
    test "analog input event_state is a constant enumeration" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{})
      type_map = object.__struct__.get_properties_type_map()

      assert PropertyEnumeration.constant_type?(type_map.event_state)
      assert PropertyEnumeration.enum_type(type_map.event_state) == :event_state
    end
  end
end
