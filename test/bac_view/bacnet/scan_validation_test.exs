defmodule BacView.BACnet.ScanValidationTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.PropertyLoad
  alias BacView.BACnet.ValidationSkipStore

  describe "recoverable_validation_error?/1" do
    test "detects value and type validation failures" do
      assert DeviceSession.recoverable_validation_error?(
               {:value_failed_property_validation, :present_value}
             )

      assert DeviceSession.recoverable_validation_error?({:invalid_property_type, :present_value})

      # ObjectsUtility decode/cast failures — shown in the error log, not skip-recoverable.
      refute DeviceSession.recoverable_validation_error?(
               {:invalid_property_value, {:network_type, 68}}
             )

      refute DeviceSession.recoverable_validation_error?(
               {:missing_optional_property, :bacnet_ip_mode}
             )

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

    test "does not offer skip modes for ObjectsUtility cast/decode failures" do
      assert DeviceSession.retry_modes_for_reason({:invalid_property_value, {:network_type, 68}}) ==
               []

      assert DeviceSession.retry_modes_for_reason({:missing_optional_property, :bacnet_ip_mode}) ==
               []
    end
  end

  describe "PropertyLoad.property_read_opts/2" do
    test "builds strict property read opts by default" do
      assert PropertyLoad.property_read_opts() == [
               allow_unknown_properties: :no_unpack,
               ignore_unsupported_object_types: true
             ]
    end

    test "includes remote_device_id when device object is known" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      assert PropertyLoad.property_read_opts(nil, device_obj) == [
               allow_unknown_properties: :no_unpack,
               ignore_unsupported_object_types: true,
               remote_device_id: 12
             ]
    end

    test "passes skip mode through object_opts for property reads" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      value_opts = PropertyLoad.property_read_opts(:value, device_obj)

      assert Keyword.get(value_opts, :remote_device_id) == 12

      assert Keyword.get(value_opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]

      all_opts = PropertyLoad.property_read_opts(true, device_obj)

      assert Keyword.get(all_opts, :object_opts) == [
               skip_property_validation_remote_object: true
             ]
    end
  end

  describe "ValidationSkipStore.from_objects/2" do
    test "reads skip mode from object summaries" do
      object_id = %ObjectIdentifier{type: :multi_state_value, instance: 42}

      assert ValidationSkipStore.from_objects(
               [
                 %{type: :multi_state_value, instance: 42, property_validation_skip_mode: :value}
               ],
               object_id
             ) == :value
    end
  end

  describe "ValidationSkipStore.apply_to_objects/3" do
    test "tags the matching object summary" do
      object_id = %ObjectIdentifier{type: :multi_state_value, instance: 42}

      objects = [
        %{type: :analog_input, instance: 1},
        %{type: :multi_state_value, instance: 42}
      ]

      assert ValidationSkipStore.apply_to_objects(objects, object_id, :value) == [
               %{type: :analog_input, instance: 1},
               %{type: :multi_state_value, instance: 42, property_validation_skip_mode: :value}
             ]
    end
  end

  describe "PropertyLoad.properties_scan_fallback_on_error?/1" do
    test "detects segmentation and property reader fallback errors" do
      assert PropertyLoad.properties_scan_fallback_on_error?(:segmentation_not_supported)
      assert PropertyLoad.properties_scan_fallback_on_error?(:buffer_overflow)
      assert PropertyLoad.properties_scan_fallback_on_error?(:object_unavailable)
      refute PropertyLoad.properties_scan_fallback_on_error?(:timeout)
    end
  end

  describe "PropertyLoad skip mode does not force scan path" do
    test "skip opts are applied without requiring upfront scan fallback" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      opts = PropertyLoad.property_read_opts(:value, device_obj)

      assert Keyword.get(opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]
    end
  end

  describe "device_object_summary/2" do
    test "builds a summary from loaded device metadata" do
      loaded = %{id: 12, instance: 12, name: "AHU-1", description: "Controller"}

      assert %{
               type: :device,
               instance: 12,
               name: "AHU-1",
               description: "Controller"
             } =
               DeviceSession.device_object_summary(loaded, %ObjectIdentifier{
                 type: :device,
                 instance: 12
               })
    end

    test "returns nil for unrelated objects" do
      loaded = %{id: 12, instance: 12, name: "AHU-1"}

      refute DeviceSession.device_object_summary(
               loaded,
               %ObjectIdentifier{type: :analog_input, instance: 1}
             )
    end
  end

  describe "PropertyLoad.scan_read_opts/2" do
    test "matches property_read_opts for the same device and skip mode" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      assert PropertyLoad.scan_read_opts(device_obj) ==
               PropertyLoad.property_read_opts(nil, device_obj)

      assert PropertyLoad.scan_read_opts(device_obj, :value) ==
               PropertyLoad.property_read_opts(:value, device_obj)

      assert PropertyLoad.scan_read_opts(device_obj, true) ==
               PropertyLoad.property_read_opts(true, device_obj)
    end

    test "builds strict scan opts by default" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      assert PropertyLoad.scan_read_opts(device_obj) == [
               allow_unknown_properties: :no_unpack,
               ignore_unsupported_object_types: true,
               remote_device_id: 12
             ]
    end

    test "passes skip mode through object_opts" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      value_opts = PropertyLoad.scan_read_opts(device_obj, :value)
      assert Keyword.get(value_opts, :allow_unknown_properties) == :no_unpack
      assert Keyword.get(value_opts, :remote_device_id) == 12

      assert Keyword.get(value_opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]

      all_opts = PropertyLoad.scan_read_opts(device_obj, true)

      assert Keyword.get(all_opts, :object_opts) == [
               skip_property_validation_remote_object: true
             ]
    end
  end
end
