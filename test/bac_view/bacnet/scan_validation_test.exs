defmodule BacView.BACnet.ScanValidationTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSession

  describe "recoverable_validation_error?/1" do
    test "detects value and type validation failures" do
      assert DeviceSession.recoverable_validation_error?(
               {:value_failed_property_validation, :present_value}
             )

      assert DeviceSession.recoverable_validation_error?({:invalid_property_type, :present_value})

      refute DeviceSession.recoverable_validation_error?(:timeout)
      refute DeviceSession.recoverable_validation_error?({:bacnet_error, %{}})
    end

    test "unwraps nested error tuples" do
      assert DeviceSession.recoverable_validation_error?(
               {:error, {:value_failed_property_validation, :present_value}}
             )
    end
  end

  describe "retry_modes_for_reason/1" do
    test "offers value and all modes for value validation failures" do
      assert DeviceSession.retry_modes_for_reason(
               {:value_failed_property_validation, :present_value}
             ) == [:value, true]
    end

    test "offers only all mode for invalid property types" do
      assert DeviceSession.retry_modes_for_reason({:invalid_property_type, :present_value}) == [
               true
             ]
    end
  end

  describe "scan_read_opts/2" do
    test "builds strict scan opts by default" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      assert DeviceSession.scan_read_opts(device_obj) == [
               allow_unknown_properties: true,
               remote_device_id: 12
             ]
    end

    test "passes skip mode through object_opts" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      value_opts = DeviceSession.scan_read_opts(device_obj, :value)
      assert Keyword.get(value_opts, :allow_unknown_properties)
      assert Keyword.get(value_opts, :remote_device_id) == 12

      assert Keyword.get(value_opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]

      all_opts = DeviceSession.scan_read_opts(device_obj, true)

      assert Keyword.get(all_opts, :object_opts) == [
               skip_property_validation_remote_object: true
             ]
    end
  end
end
