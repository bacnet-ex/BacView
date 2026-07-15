defmodule BacView.BACnet.Protocol.PropertyFormatterTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{ObjectIdentifier, Recipient, RecipientAddress}
  alias BacView.BACnet.Protocol.PropertyFormatter

  describe "decimal_places_from_resolution/1" do
    test "derives decimal places from resolution" do
      assert PropertyFormatter.decimal_places_from_resolution(1.0) == 0
      assert PropertyFormatter.decimal_places_from_resolution(1) == 0
      assert PropertyFormatter.decimal_places_from_resolution(0.1) == 1
      assert PropertyFormatter.decimal_places_from_resolution(0.01) == 2
      assert PropertyFormatter.decimal_places_from_resolution(nil) == nil
    end
  end

  describe "format_float/1" do
    test "never uses scientific notation for very small values" do
      assert PropertyFormatter.format_float(1.0e-5) == "0.00001"
      assert PropertyFormatter.format_float(2.5e-8) == "0.000000025"
    end

    test "trims unnecessary trailing zeros but keeps at least one decimal place" do
      assert PropertyFormatter.format_float(21.5) == "21.5"
      assert PropertyFormatter.format_float(21.0) == "21.0"
      assert PropertyFormatter.format_float(0.0) == "0.0"
      assert PropertyFormatter.format_float(22.0000000000) == "22.0"
    end

    test "preserves meaningful decimal precision" do
      assert PropertyFormatter.format_float(3.14159) == "3.14159"
      assert PropertyFormatter.format_float(0.1) == "0.1"
    end

    test "formats without decimals when resolution is 1.0" do
      assert PropertyFormatter.format_float(22.0, 1.0) == "22"
      assert PropertyFormatter.format_float(21.5, 1.0) == "22"
    end

    test "formats with fixed decimals when resolution is set" do
      assert PropertyFormatter.format_float(22.0, 0.1) == "22.0"
      assert PropertyFormatter.format_float(22.0, 0.01) == "22.00"
    end
  end

  describe "format_value/2 for PriorityArray" do
    test "shows active priority and value" do
      pa = %BACnet.Protocol.PriorityArray{priority_8: 21.5, priority_16: 99.0}

      assert PropertyFormatter.format_value(pa, nil) == "21.5 (P8)"
    end
  end

  describe "format_edit_value/3" do
    test "formats analog present value edit input without unnecessary decimals" do
      object = %{type: :analog_value, units: nil}

      assert PropertyFormatter.format_edit_value(22.0, object, %{property: :present_value}) ==
               "22"

      assert PropertyFormatter.format_edit_value(21.5, object, %{property: :present_value}) ==
               "21.5"

      assert PropertyFormatter.format_edit_value(22, object, %{property: :present_value}) == "22"
    end

    test "formats analog present value edit input using resolution" do
      object = %{type: :analog_input, units: nil, resolution: 1.0}

      assert PropertyFormatter.format_edit_value(22.0, object, %{property: :present_value}) ==
               "22"
    end

    test "keeps generic real property edit formatting for non-present values" do
      object = %{type: :analog_input, units: nil, resolution: 1.0}
      prop = %{property: :cov_increment, type: "REAL"}

      assert PropertyFormatter.format_edit_value(1.0, object, prop) == "1.0"
    end
  end

  describe "format_present_value/3" do
    test "formats binary object integers as true/false" do
      object = %{type: :binary_value, units: nil}

      assert PropertyFormatter.format_present_value(1, object) == "true"
      assert PropertyFormatter.format_present_value(0, object) == "false"
      assert PropertyFormatter.coerce_present_value(1, object) == true
    end

    test "formats integer analog present values without decimals" do
      object = %{type: :analog_value, units: nil}

      assert PropertyFormatter.format_present_value(1, object) == "1"
      assert PropertyFormatter.format_present_value(22, object) == "22"
      assert PropertyFormatter.coerce_present_value(1, object) == 1
    end

    test "formats float analog present values with decimals only when needed" do
      object = %{type: :analog_value, units: nil}

      assert PropertyFormatter.format_present_value(21.5, object) == "21.5"
      assert PropertyFormatter.format_present_value(22.0, object) == "22"
    end

    test "formats analog present values with units" do
      object = %{type: :analog_input, units: :degrees_celsius}

      assert PropertyFormatter.format_present_value(22, object) == "22 °C"
      assert PropertyFormatter.format_present_value(22.0, object) == "22 °C"
      assert PropertyFormatter.format_present_value(21.5, object) == "21.5 °C"
    end

    test "formats analog present values without decimals when resolution is 1.0" do
      object = %{type: :analog_value, units: nil, resolution: 1.0}

      assert PropertyFormatter.format_present_value(22.0, object) == "22"
      assert PropertyFormatter.format_present_value(21.5, object) == "22"
    end

    test "formats analog present values with decimals derived from resolution" do
      object = %{type: :analog_input, units: nil, resolution: 0.1}

      assert PropertyFormatter.format_present_value(22.0, object) == "22.0"
      assert PropertyFormatter.format_present_value(21.55, object) == "21.6"
    end

    test "formats analog present values with units and resolution" do
      object = %{type: :analog_input, units: :degrees_celsius, resolution: 1.0}

      assert PropertyFormatter.format_present_value(22.0, object) == "22 °C"
    end

    test "formats multistate present values with active state text" do
      object = %{
        type: :multi_state_value,
        number_of_states: 2,
        state_text: ["Off", "On"]
      }

      assert PropertyFormatter.format_present_value(2, object) == "2 (On)"
    end
  end

  describe "format_value/2" do
    test "formats floats with units without scientific notation" do
      assert PropertyFormatter.format_value(1.0e-5, "°C") == "0.00001 °C"
      assert PropertyFormatter.format_value(21.5, "kW") == "21.5 kW"
    end

    test "formats floats without units without scientific notation" do
      assert PropertyFormatter.format_value(1.0e-5, nil) == "0.00001"
      assert PropertyFormatter.format_value(1234.5678, nil) == "1234.5678"
    end

    test "unwraps BACnet Encoding and preserves units" do
      encoding = %BACnet.Protocol.ApplicationTags.Encoding{
        encoding: :primitive,
        type: :real,
        value: 21.5,
        extras: []
      }

      assert PropertyFormatter.format_value(encoding, :percent) == "REAL: 21.5 %"
      assert PropertyFormatter.format_value(encoding, :degrees_celsius) == "REAL: 21.5 °C"
    end

    test "formats six-byte BACnet/IP addresses as IPv4 with port" do
      address = %RecipientAddress{network: 0, address: <<192, 168, 1, 73, 186, 192>>}

      assert PropertyFormatter.format_mac_address(address.address) == "192.168.1.73:47808"
      assert PropertyFormatter.format_value(address, nil) == "0/192.168.1.73:47808"
    end

    test "falls back to hex for six-byte addresses with invalid port" do
      assert PropertyFormatter.format_mac_address(<<192, 168, 1, 73, 0, 0>>) ==
               "C0:A8:01:49:00:00"
    end

    test "formats non-six-byte addresses as hex" do
      assert PropertyFormatter.format_mac_address(<<1, 2, 3, 4, 5>>) == "01:02:03:04:05"
    end

    test "format_binary_hex renders uppercase byte groups" do
      assert PropertyFormatter.format_binary_hex("AB") == "41:42"
      assert PropertyFormatter.format_binary_hex(<<0>>) == "00"
    end

    test "formats recipient device and broadcast addresses" do
      device_recipient = %Recipient{
        type: :device,
        device: %ObjectIdentifier{type: :device, instance: 100},
        address: nil
      }

      broadcast_recipient = %Recipient{
        type: :address,
        device: nil,
        address: %RecipientAddress{network: 1, address: :broadcast}
      }

      assert PropertyFormatter.format_value(device_recipient, nil) == "device:100"
      assert PropertyFormatter.format_value(broadcast_recipient, nil) == "1/broadcast"
    end
  end

  describe "property_type/1" do
    test "returns BITSTRING for boolean tuples" do
      assert PropertyFormatter.property_type({true, false, false, true}) == "BITSTRING"
      assert PropertyFormatter.property_type({:bitstring, {false, true}}) == "BITSTRING"
    end

    test "returns BITSTRING for Encoding bitstring values" do
      encoding = %BACnet.Protocol.ApplicationTags.Encoding{
        encoding: :primitive,
        type: :bitstring,
        value: {false, false, false, true},
        extras: []
      }

      assert PropertyFormatter.property_type(encoding) == "BITSTRING"
    end

    test "does not treat non-boolean tuples as bitstrings" do
      assert PropertyFormatter.property_type({192, 168, 1, 1}) == "STRUCT"
    end

    test "labels BACnetArray as ARRAY and plain lists as LIST" do
      assert PropertyFormatter.property_type(BACnet.Protocol.BACnetArray.from_list([1])) ==
               "ARRAY"

      assert PropertyFormatter.property_type([1]) == "LIST"
    end

    test "returns signed and unsigned labels for Encoding integers" do
      unsigned = %BACnet.Protocol.ApplicationTags.Encoding{
        encoding: :primitive,
        type: :unsigned_integer,
        value: 3,
        extras: []
      }

      signed = %BACnet.Protocol.ApplicationTags.Encoding{
        encoding: :primitive,
        type: :signed_integer,
        value: -3,
        extras: []
      }

      assert PropertyFormatter.property_type(unsigned) == "UNSIGNED INTEGER"
      assert PropertyFormatter.property_type(signed) == "SIGNED INTEGER"
    end

    test "keeps generic INTEGER label without schema" do
      assert PropertyFormatter.property_type(42) == "INTEGER"
      assert PropertyFormatter.property_type(-3) == "INTEGER"
    end
  end

  describe "integer_bac_type_label/1" do
    test "unwraps schema integer types" do
      assert PropertyFormatter.integer_bac_type_label(:unsigned_integer) == "UNSIGNED INTEGER"
      assert PropertyFormatter.integer_bac_type_label(:signed_integer) == "SIGNED INTEGER"

      assert PropertyFormatter.integer_bac_type_label(
               {:with_validator, :unsigned_integer, &(&1 >= 1)}
             ) == "UNSIGNED INTEGER"

      assert PropertyFormatter.integer_bac_type_label(
               {:type_list, [:unsigned_integer, {:literal, nil}]}
             ) == "UNSIGNED INTEGER"
    end

    test "returns nil for non-integer schema types" do
      assert PropertyFormatter.integer_bac_type_label(:real) == nil
      assert PropertyFormatter.integer_bac_type_label({:constant, :event_state}) == nil
    end
  end

  describe "property_type_tooltip/1" do
    test "returns struct name for STRUCT properties" do
      flags = %BACnet.Protocol.StatusFlags{
        in_alarm: false,
        fault: true,
        overridden: false,
        out_of_service: false
      }

      prop = %{
        type: "STRUCT",
        value: flags,
        value_display: %{kind: :struct, fields: [], items: []}
      }

      assert PropertyFormatter.property_type_tooltip(prop) == "BACnet.Protocol.StatusFlags"
    end

    test "returns ARRAY OF INTEGER for homogeneous BACnetArray values" do
      array = BACnet.Protocol.BACnetArray.from_list([1, 2])

      prop = %{
        type: "ARRAY",
        value: array,
        value_display: %{kind: :array, items: [%{value: 1}, %{value: 2}]}
      }

      assert PropertyFormatter.property_type_tooltip(prop) == "ARRAY OF INTEGER"
    end

    test "returns ARRAY OF subtype from schema when BACnetArray is empty" do
      prop = %{
        type: "ARRAY",
        value: BACnet.Protocol.BACnetArray.new(),
        bac_type: {:array, :unsigned_integer},
        value_display: %{kind: :array, items: []}
      }

      assert PropertyFormatter.property_type_tooltip(prop) == "ARRAY OF UNSIGNED INTEGER"
    end

    test "returns plain ARRAY for mixed-type BACnetArray without schema" do
      array = BACnet.Protocol.BACnetArray.from_list([1, 2.0])

      prop = %{
        type: "ARRAY",
        value: array,
        value_display: %{kind: :array, items: [%{value: 1}, %{value: 2.0}]}
      }

      assert PropertyFormatter.property_type_tooltip(prop) == "ARRAY"
    end

    test "returns LIST OF INTEGER for homogeneous plain lists" do
      prop = %{
        type: "LIST",
        value: [1, 2],
        value_display: %{kind: :list, items: [%{value: 1}, %{value: 2}]}
      }

      assert PropertyFormatter.property_type_tooltip(prop) == "LIST OF INTEGER"
    end

    test "returns LIST OF subtype from schema for plain lists" do
      prop = %{
        type: "LIST",
        value: [],
        bac_type: {:list, :bitstring},
        value_display: %{kind: :list, items: []}
      }

      assert PropertyFormatter.property_type_tooltip(prop) == "LIST OF BITSTRING"
    end

    test "returns nil for non-STRUCT types" do
      prop = %{type: "REAL", value: 1.0, value_display: %{kind: :scalar}}

      assert PropertyFormatter.property_type_tooltip(prop) == nil
    end
  end
end
