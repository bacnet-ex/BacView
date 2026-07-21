defmodule BacView.BACnet.Protocol.PropertyWriterTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.PropertyWriter

  describe "parse_input/2" do
    test "parses real numbers" do
      assert PropertyWriter.parse_input("21.5", %{type: "REAL"}) == {:ok, 21.5}
    end

    test "parses booleans" do
      assert PropertyWriter.parse_input("true", %{type: "BOOLEAN"}) == {:ok, true}
      assert PropertyWriter.parse_input("false", %{type: "BOOLEAN"}) == {:ok, false}
    end

    test "accepts nil reset aliases" do
      for alias <- ["null", "nil", "reset", "relinquish", "-"] do
        assert PropertyWriter.parse_input(alias, %{type: "REAL"}) == {:ok, nil}
      end
    end

    test "parses character string properties" do
      assert PropertyWriter.parse_input("Room sensor", %{type: "CHARACTER STRING"}) ==
               {:ok, "Room sensor"}

      assert PropertyWriter.parse_input("not-a-number", %{type: "CHARACTER STRING"}) ==
               {:ok, "not-a-number"}
    end

    test "infers character string from current value or bac_type" do
      assert PropertyWriter.parse_input("updated", %{value: "original"}) == {:ok, "updated"}

      assert PropertyWriter.parse_input("new text", %{bac_type: :string, value: nil}) ==
               {:ok, "new text"}
    end
  end

  describe "parse_hex_input/1" do
    test "parses colon-separated and plain hex" do
      assert PropertyWriter.parse_hex_input("41:00:42") == {:ok, <<0x41, 0, 0x42>>}
      assert PropertyWriter.parse_hex_input("410042") == {:ok, <<0x41, 0, 0x42>>}
      assert PropertyWriter.parse_hex_input("41 00 42") == {:ok, <<0x41, 0, 0x42>>}
    end

    test "rejects invalid hex" do
      assert PropertyWriter.parse_hex_input("") == {:error, :empty_value}
      assert PropertyWriter.parse_hex_input("41:0") == {:error, :invalid_hex}
      assert PropertyWriter.parse_hex_input("zz") == {:error, :invalid_hex}
    end
  end

  describe "parse_write_params with hex encoding" do
    test "parses hex when encoding is hex" do
      prop = %{
        type: "CHARACTER STRING",
        value: "ab",
        value_display: %{kind: :scalar, formatted: "ab", fields: [], items: []}
      }

      assert PropertyWriter.parse_write_params(
               %{"value" => "61:00:62", "encoding" => "hex"},
               prop
             ) == {:ok, <<0x61, 0, 0x62>>}
    end
  end

  describe "write_opts/3" do
    test "includes priority for commandable present_value" do
      object = %{commandable: true}

      assert PropertyWriter.write_opts(object, :present_value, 8) == [priority: 8]
    end

    test "includes priority when object has a priority array" do
      object = %{priority_array: %BACnet.Protocol.PriorityArray{priority_8: 21.0}}

      assert PropertyWriter.write_opts(object, :present_value, 8) == [priority: 8]
    end

    test "omits priority for non-commandable objects" do
      assert PropertyWriter.write_opts(%{commandable: false}, :present_value, 8) == []
      assert PropertyWriter.write_opts(%{type: :analog_input}, :present_value, 8) == []
      assert PropertyWriter.write_opts(%{type: :binary_value}, :present_value, 8) == []
    end
  end

  describe "commandable_for_ui?/1" do
    test "uses summary commandable flag when present" do
      assert PropertyWriter.commandable_for_ui?(%{commandable: true})
      refute PropertyWriter.commandable_for_ui?(%{commandable: false, type: :binary_value})
    end

    test "detects priority array on BACnet objects" do
      {:ok, ao} = BACnet.Protocol.ObjectTypes.AnalogOutput.create(1, "AO", %{})
      {:ok, bv} = BACnet.Protocol.ObjectTypes.BinaryValue.create(1, "BV", %{})

      assert PropertyWriter.commandable_for_ui?(ao)
      refute PropertyWriter.commandable_for_ui?(bv)
    end
  end

  describe "priority_slot_value/2" do
    test "reads the value at the given priority" do
      pa = %BACnet.Protocol.PriorityArray{priority_8: 21.0}

      assert PropertyWriter.priority_slot_value(pa, 8) == 21.0
      assert PropertyWriter.priority_slot_value(pa, 1) == nil
    end
  end

  describe "enrich_properties/2" do
    test "marks properties flagged writable by the reader" do
      props = [%{property: :limit_enable, writable: true}]

      [enriched] = PropertyWriter.enrich_properties(props, %{})
      assert enriched.writable
    end

    test "leaves non-writable properties unchanged" do
      props = [%{property: :status_flags, writable: false}]

      [enriched] = PropertyWriter.enrich_properties(props, %{})
      refute enriched.writable
    end

    test "marks present_value writable for commandable objects" do
      props = [%{property: :present_value, writable: false}]
      object = %{commandable: true, type: :analog_output}

      [enriched] = PropertyWriter.enrich_properties(props, object)
      assert enriched.writable
    end

    test "does not mark present_value writable for non-commandable binary values" do
      props = [%{property: :present_value, writable: false}]
      object = %{commandable: false, type: :binary_value}

      [enriched] = PropertyWriter.enrich_properties(props, object)
      refute enriched.writable
    end
  end

  describe "parse_write_params/2" do
    test "parses boolean properties from checkbox params" do
      prop = %{
        property: :out_of_service,
        bac_type: :boolean,
        type: "BOOLEAN",
        value: false,
        value_display: %{kind: :scalar, formatted: "false"}
      }

      assert PropertyWriter.parse_write_params(%{"value" => "true"}, prop) == {:ok, true}

      assert PropertyWriter.parse_write_params(%{"value" => ["false", "true"]}, prop) ==
               {:ok, true}
    end

    test "parses enumeration properties from select params" do
      prop = %{
        property: :event_state,
        enum_type: :event_state,
        value: :normal,
        value_display: %{kind: :scalar, formatted: "Normal"}
      }

      assert PropertyWriter.parse_write_params(%{"value" => "fault"}, prop) == {:ok, :fault}
    end

    test "rejects invalid enumeration values" do
      prop = %{
        property: :event_state,
        enum_type: :event_state,
        value: :normal,
        value_display: %{kind: :scalar, formatted: "Normal"}
      }

      assert PropertyWriter.parse_write_params(%{"value" => "bogus"}, prop) ==
               {:error, :invalid_enum}
    end

    test "parses character string properties from text input" do
      prop = %{
        property: :description,
        bac_type: :string,
        type: "CHARACTER STRING",
        value: "Original description",
        value_display: %{kind: :scalar, formatted: "Original description"}
      }

      assert PropertyWriter.parse_write_params(%{"value" => "Updated description"}, prop) ==
               {:ok, "Updated description"}
    end

    test "parses boolean struct properties from checkbox params" do
      enable = %BACnet.Protocol.LimitEnable{low_limit_enable: false, high_limit_enable: true}

      prop = %{
        property: :limit_enable,
        value: enable,
        value_display: %{
          kind: :struct,
          fields: [
            %{key: :low_limit_enable, kind: :boolean},
            %{key: :high_limit_enable, kind: :boolean}
          ]
        }
      }

      params = %{
        "limit_enable_low_limit_enable" => "true",
        "limit_enable_high_limit_enable" => "false"
      }

      assert PropertyWriter.parse_write_params(params, prop) ==
               {:ok,
                %BACnet.Protocol.LimitEnable{low_limit_enable: true, high_limit_enable: false}}
    end
  end

  test "default_priority is 8" do
    assert PropertyWriter.default_priority() == 8
  end

  describe "active_priority_info/1" do
    test "returns lowest priority number with a non-nil value" do
      pa = %BACnet.Protocol.PriorityArray{priority_8: 21.0, priority_16: 99.0}

      info = PropertyWriter.active_priority_info(%{priority_array: pa, units: nil})

      assert info.active_priority == 8
      assert info.active_priority_value_formatted == "21.0"
    end

    test "returns nil when all priorities are relinquished" do
      info =
        PropertyWriter.active_priority_info(%{priority_array: %BACnet.Protocol.PriorityArray{}})

      assert info.active_priority == nil
      assert info.active_priority_value_formatted == nil
    end
  end

  describe "values_match?/2" do
    test "matches exact values" do
      assert PropertyWriter.values_match?(21.5, 21.5)
      assert PropertyWriter.values_match?(true, true)
      assert PropertyWriter.values_match?(42, 42)
    end

    test "matches floats within tolerance" do
      assert PropertyWriter.values_match?(21.5, 21.50001)
      assert PropertyWriter.values_match?(1, 1.0)
    end

    test "accepts any read value after null write" do
      assert PropertyWriter.values_match?(nil, 21.5)
      assert PropertyWriter.values_match?(nil, nil)
    end

    test "rejects mismatched values" do
      refute PropertyWriter.values_match?(21.5, 22.0)
      refute PropertyWriter.values_match?(true, false)
    end

    test "matches BACnetArray elements regardless of internal storage defaults" do
      alias BACnet.Protocol.{BACnetArray, DeviceObjectPropertyRef, ObjectIdentifier}

      ref = %DeviceObjectPropertyRef{
        object_identifier: %ObjectIdentifier{type: :multi_state_value, instance: 213},
        property_identifier: :present_value,
        property_array_index: nil,
        device_identifier: nil
      }

      {:ok, written} =
        BACnetArray.set_item(
          BACnetArray.from_list([], false, ref),
          1,
          ref
        )

      {:ok, read} = BACnetArray.set_item(BACnetArray.new(), 1, ref)

      assert PropertyWriter.values_match?(written, read)
    end

    test "rejects BACnetArray with different elements" do
      alias BACnet.Protocol.{BACnetArray, DeviceObjectPropertyRef, ObjectIdentifier}

      ref = %DeviceObjectPropertyRef{
        object_identifier: %ObjectIdentifier{type: :multi_state_value, instance: 213},
        property_identifier: :present_value,
        property_array_index: nil,
        device_identifier: nil
      }

      other = %DeviceObjectPropertyRef{
        ref
        | object_identifier: %{ref.object_identifier | instance: 99}
      }

      {:ok, written} = BACnetArray.set_item(BACnetArray.new(), 1, ref)
      {:ok, read} = BACnetArray.set_item(BACnetArray.new(), 1, other)

      refute PropertyWriter.values_match?(written, read)
    end
  end

  test "prop_hint_from_object infers type from present value" do
    hint = PropertyWriter.prop_hint_from_object(%{present_value: 12.5, units: :degrees_celsius})
    assert hint.type == "REAL"
    assert hint.value == 12.5
  end
end
