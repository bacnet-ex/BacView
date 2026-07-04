defmodule BacView.BACnet.Protocol.PropertyFormatterTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{ObjectIdentifier, Recipient, RecipientAddress}
  alias BacView.BACnet.Protocol.PropertyFormatter

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
    end
  end

  describe "format_value/2 for PriorityArray" do
    test "shows active priority and value" do
      pa = %BACnet.Protocol.PriorityArray{priority_8: 21.5, priority_16: 99.0}

      assert PropertyFormatter.format_value(pa, nil) == "21.5 (P8)"
    end
  end

  describe "format_present_value/3" do
    test "formats binary object integers as true/false" do
      object = %{type: :binary_value, units: nil}

      assert PropertyFormatter.format_present_value(1, object) == "true"
      assert PropertyFormatter.format_present_value(0, object) == "false"
      assert PropertyFormatter.coerce_present_value(1, object) == true
    end

    test "formats analog present values with at least one decimal place" do
      object = %{type: :analog_value, units: nil}

      assert PropertyFormatter.format_present_value(1, object) == "1.0"
      assert PropertyFormatter.format_present_value(21.5, object) == "21.5"
      assert PropertyFormatter.format_present_value(22.0, object) == "22.0"
      assert PropertyFormatter.coerce_present_value(1, object) == 1
    end

    test "formats analog present values with units" do
      object = %{type: :analog_input, units: :degrees_celsius}

      assert PropertyFormatter.format_present_value(22.0, object) == "22.0 °C"
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
end
