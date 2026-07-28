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

  describe "format_constant/2" do
    test "formats notify_type atoms and integers like known properties" do
      assert PropertyEnumeration.format_constant(:notify_type, :alarm) == "alarm (0)"
      assert PropertyEnumeration.format_constant(:notify_type, 0) == "alarm (0)"
      assert PropertyEnumeration.format_constant(:notify_type, :event) == "event (1)"
      assert PropertyEnumeration.format_constant(:notify_type, 1) == "event (1)"
    end

    test "returns nil for non-constant property types" do
      assert PropertyEnumeration.format_constant(:vendor_prop, :alarm) == nil
      assert PropertyEnumeration.format_constant(512, :alarm) == nil
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
      assert enriched.value_formatted == "normal (0)"
    end

    test "attaches dropdown options for in_list property types" do
      bac_type =
        {:in_list, [:confirmed_cov_if_possible, :polling, :unconfirmed_cov_if_possible]}

      prop = %{
        property: :subscription_type,
        value: :polling,
        value_display: %{kind: :scalar, formatted: "polling", fields: [], items: []},
        value_formatted: "polling",
        type: "ENUMERATED",
        bac_type: bac_type
      }

      enriched = PropertyEnumeration.enrich_property(prop, bac_type)

      refute Map.has_key?(enriched, :enum_type)
      assert enriched.type == "ENUMERATED"
      assert PropertyEnumeration.dropdown?(enriched)

      assert Enum.map(enriched.enum_options, & &1.value) == [
               :confirmed_cov_if_possible,
               :polling,
               :unconfirmed_cov_if_possible
             ]

      assert enriched.value_formatted == "polling"
      assert Enum.find(enriched.enum_options, &(&1.value == :polling)).label == "polling"
    end

    test "does not attach dropdown options when in_list is not all atoms" do
      bac_type = {:in_list, [:polling, 1, "mixed"]}

      prop = %{
        property: :custom_prop,
        value: :polling,
        value_display: %{kind: :scalar, formatted: "polling", fields: [], items: []},
        value_formatted: "polling",
        type: "ENUMERATED",
        bac_type: bac_type
      }

      enriched = PropertyEnumeration.enrich_property(prop, bac_type)

      refute PropertyEnumeration.in_list_type?(bac_type)
      refute PropertyEnumeration.atom_in_list?(elem(bac_type, 1))
      assert PropertyEnumeration.in_list_options(elem(bac_type, 1)) == []
      assert enriched.enum_options in [nil, []]
      refute PropertyEnumeration.dropdown?(enriched)
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

    test "keeps dropdown when options are present even for unknown integer values" do
      prop = %{
        value: 99,
        enum_options: PropertyEnumeration.options(:event_state)
      }

      assert PropertyEnumeration.dropdown?(prop)
    end

    test "uses dropdown when value is nil" do
      prop = %{
        value: nil,
        enum_options: [%{value: 1, label: "1"}]
      }

      assert PropertyEnumeration.dropdown?(prop)
    end
  end

  describe "enrich_property/2 with numeric constants" do
    test "injects synthetic option and formats unknown integer constant" do
      prop = %{
        property: :event_state,
        value: 99,
        value_display: %{kind: :scalar, formatted: "99", fields: [], items: []},
        type: "ENUMERATED"
      }

      enriched = PropertyEnumeration.enrich_property(prop, {:constant, :event_state})

      assert enriched.enum_type == :event_state
      assert Enum.any?(enriched.enum_options, &(&1.value == 99))
      assert Enum.any?(enriched.enum_options, &(&1.value == :normal))
      assert enriched.value_formatted == "99"
      assert PropertyEnumeration.dropdown?(enriched)
    end
  end

  describe "free_input_value_string/2" do
    test "maps constant atoms to their integer value" do
      assert PropertyEnumeration.free_input_value_string(:no_fault_detected, :reliability) == "0"
      assert PropertyEnumeration.free_input_value_string(:normal, :event_state) == "0"
    end

    test "keeps integers as decimal strings" do
      assert PropertyEnumeration.free_input_value_string(99, :event_state) == "99"
    end

    test "falls back to atom name without enum type" do
      assert PropertyEnumeration.free_input_value_string(:polling, nil) == "polling"
    end
  end

  describe "parse_value/2" do
    test "accepts valid enum atoms" do
      assert PropertyEnumeration.parse_value("normal", :event_state) == {:ok, :normal}
    end

    test "accepts unknown non-negative integers for vendor constants" do
      assert PropertyEnumeration.parse_value("99", :event_state) == {:ok, 99}
    end

    test "maps known numeric constants to their atom name" do
      assert PropertyEnumeration.parse_value("0", :event_state) == {:ok, :normal}
    end

    test "rejects unknown enum values" do
      assert PropertyEnumeration.parse_value("not_a_state", :event_state) ==
               {:error, :invalid_enum}
    end

    test "rejects negative integers" do
      assert PropertyEnumeration.parse_value("-1", :event_state) == {:error, :invalid_enum}
    end
  end

  describe "parse_option_value/2" do
    test "accepts in_list atoms from select params" do
      options =
        PropertyEnumeration.in_list_options([
          :confirmed_cov_if_possible,
          :polling,
          :unconfirmed_cov_if_possible
        ])

      assert PropertyEnumeration.parse_option_value("polling", options) == {:ok, :polling}
    end

    test "accepts multistate integer options" do
      options = [%{value: 1, label: "Off"}, %{value: 2, label: "On"}]

      assert PropertyEnumeration.parse_option_value("2", options) == {:ok, 2}
    end

    test "accepts free non-negative integers outside the option list" do
      options = PropertyEnumeration.in_list_options([:polling, :confirmed_cov_if_possible])

      assert PropertyEnumeration.parse_option_value("42", options) == {:ok, 42}
    end

    test "rejects non-numeric values outside the option list" do
      options = PropertyEnumeration.in_list_options([:polling, :confirmed_cov_if_possible])

      assert PropertyEnumeration.parse_option_value("not_an_option", options) ==
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

    test "event enrollment subscription_type is an in_list enumeration" do
      type_map = BACnet.Protocol.ObjectTypes.EventEnrollment.get_properties_type_map()
      bac_type = type_map.subscription_type

      assert PropertyEnumeration.in_list_type?(bac_type)
      refute PropertyEnumeration.constant_type?(bac_type)

      options = PropertyEnumeration.in_list_options(elem(bac_type, 1))
      assert Enum.any?(options, &(&1.value == :polling))
    end
  end
end
