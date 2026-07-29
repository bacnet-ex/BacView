defmodule BacView.BACnet.ScanValidationTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.PropertyLoad
  alias BacView.BACnet.ValidationSkipStore

  describe "recoverable_validation_error?/1" do
    test "detects validation and cast/decode failures that offer recovery" do
      assert DeviceSession.recoverable_validation_error?(
               {:value_failed_property_validation, :present_value}
             )

      assert DeviceSession.recoverable_validation_error?({:invalid_property_type, :present_value})

      assert DeviceSession.recoverable_validation_error?(
               {:invalid_property_value, {:network_type, 68}}
             )

      assert DeviceSession.recoverable_validation_error?({:missing_parse_fun, :present_value})

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

  describe "object_ids_for_scan/2" do
    test "excludes the device object so it is not double-read during scan" do
      device = %ObjectIdentifier{type: :device, instance: 411_6080}
      ai = %ObjectIdentifier{type: :analog_input, instance: 1}
      av = %ObjectIdentifier{type: :analog_value, instance: 2}

      assert DeviceSession.object_ids_for_scan([device, ai, av, device], device) == [ai, av]
      assert DeviceSession.object_ids_for_scan([ai, av], device) == [ai, av]
      assert DeviceSession.object_ids_for_scan([], device) == []
    end
  end

  describe "device_object_load_recovery/1" do
    test "offers recovery modes when the device object read failed recoverably" do
      assert DeviceSession.device_object_load_recovery(
               {:device_object_read_failed, {:invalid_property_value, {:tags, []}}}
             ) == %{
               reason: {:invalid_property_value, {:tags, []}},
               retry_modes: [:ignore_invalid, :skip_all_and_ignore_invalid]
             }

      assert DeviceSession.device_object_load_recovery(
               {:device_object_read_failed, {:value_failed_property_validation, :present_value}}
             ) == %{
               reason: {:value_failed_property_validation, :present_value},
               retry_modes: [:value, :ignore_invalid, true, :skip_all_and_ignore_invalid]
             }
    end

    test "returns nil for non-recoverable or non-device-object failures" do
      refute DeviceSession.device_object_load_recovery({:device_object_read_failed, :timeout})

      refute DeviceSession.device_object_load_recovery({:invalid_property_value, {:tags, []}})

      refute DeviceSession.device_object_load_recovery(:stack_not_started)
    end
  end

  describe "retry_modes_for_reason/1" do
    test "offers value, ignore-invalid, all, and maximal modes for value validation failures" do
      assert DeviceSession.retry_modes_for_reason(
               {:value_failed_property_validation, :present_value}
             ) == [:value, :ignore_invalid, true, :skip_all_and_ignore_invalid]
    end

    test "offers ignore-invalid, all, and maximal modes for invalid property types" do
      assert DeviceSession.retry_modes_for_reason({:invalid_property_type, :present_value}) == [
               :ignore_invalid,
               true,
               :skip_all_and_ignore_invalid
             ]
    end

    test "offers ignore-invalid and maximal for ObjectsUtility cast/decode failures" do
      assert DeviceSession.retry_modes_for_reason({:invalid_property_value, {:network_type, 68}}) ==
               [:ignore_invalid, :skip_all_and_ignore_invalid]

      assert DeviceSession.retry_modes_for_reason({:missing_parse_fun, :present_value}) == [
               :ignore_invalid,
               :skip_all_and_ignore_invalid
             ]

      assert DeviceSession.retry_modes_for_reason({:missing_optional_property, :bacnet_ip_mode}) ==
               []
    end
  end

  describe "property_read_recovery/1" do
    test "returns modes for recoverable property load failures" do
      assert DeviceSession.property_read_recovery({:invalid_property_value, {:tags, []}}) == %{
               reason: {:invalid_property_value, {:tags, []}},
               retry_modes: [:ignore_invalid, :skip_all_and_ignore_invalid]
             }
    end

    test "returns nil for non-recoverable failures" do
      refute DeviceSession.property_read_recovery(:timeout)
    end
  end

  describe "parse_recovery_mode/1" do
    test "parses known recovery modes" do
      assert DeviceSession.parse_recovery_mode("value") == {:ok, :value}
      assert DeviceSession.parse_recovery_mode("ignore-invalid") == {:ok, :ignore_invalid}
      assert DeviceSession.parse_recovery_mode("all") == {:ok, true}

      assert DeviceSession.parse_recovery_mode("skip-all-and-ignore-invalid") ==
               {:ok, :skip_all_and_ignore_invalid}

      assert DeviceSession.parse_recovery_mode("nope") == :error
    end
  end

  describe "PropertyLoad.property_read_opts/2" do
    test "builds property read opts with numeric constants enabled by default" do
      opts = PropertyLoad.property_read_opts()

      assert Keyword.get(opts, :allow_unknown_properties) == :no_unpack
      assert Keyword.get(opts, :ignore_unsupported_object_types) == true
      assert Keyword.get(opts, :allow_numeric_constants) == true
      assert Keyword.get(opts, :object_opts) == [allow_numeric_constants: true]
    end

    test "includes remote_device_id when device object is known" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      opts = PropertyLoad.property_read_opts(nil, device_obj)

      assert Keyword.get(opts, :allow_unknown_properties) == :no_unpack
      assert Keyword.get(opts, :ignore_unsupported_object_types) == true
      assert Keyword.get(opts, :remote_device_id) == 12
      assert Keyword.get(opts, :allow_numeric_constants) == true
      assert Keyword.get(opts, :object_opts) == [allow_numeric_constants: true]
    end

    test "passes skip mode through object_opts for property reads" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      value_opts = PropertyLoad.property_read_opts(:value, device_obj)

      assert Keyword.get(value_opts, :remote_device_id) == 12
      assert Keyword.get(value_opts, :allow_numeric_constants) == true

      object_opts = Keyword.get(value_opts, :object_opts)
      assert Keyword.get(object_opts, :allow_numeric_constants) == true
      assert Keyword.get(object_opts, :skip_property_validation_remote_object) == :value

      all_opts = PropertyLoad.property_read_opts(true, device_obj)
      all_object_opts = Keyword.get(all_opts, :object_opts)
      assert Keyword.get(all_object_opts, :allow_numeric_constants) == true
      assert Keyword.get(all_object_opts, :skip_property_validation_remote_object) == true
    end

    test "passes ignore_invalid_properties for ignore_invalid recovery mode" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      opts = PropertyLoad.property_read_opts(:ignore_invalid, device_obj)

      assert Keyword.get(opts, :ignore_invalid_properties) == true
      assert Keyword.get(opts, :remote_device_id) == 12
      assert Keyword.get(opts, :allow_numeric_constants) == true

      object_opts = Keyword.get(opts, :object_opts)
      assert Keyword.get(object_opts, :allow_numeric_constants) == true
      refute Keyword.has_key?(object_opts, :skip_property_validation_remote_object)
    end

    test "combines skip-all and ignore-invalid for maximal recovery mode" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      opts = PropertyLoad.property_read_opts(:skip_all_and_ignore_invalid, device_obj)

      assert Keyword.get(opts, :ignore_invalid_properties) == true
      object_opts = Keyword.get(opts, :object_opts)
      assert Keyword.get(object_opts, :skip_property_validation_remote_object) == true
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
      object_opts = Keyword.get(opts, :object_opts)

      assert Keyword.get(object_opts, :skip_property_validation_remote_object) == :value
      assert Keyword.get(object_opts, :allow_numeric_constants) == true
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

    test "builds scan opts with numeric constants enabled by default" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      opts = PropertyLoad.scan_read_opts(device_obj)

      assert Keyword.get(opts, :allow_unknown_properties) == :no_unpack
      assert Keyword.get(opts, :ignore_unsupported_object_types) == true
      assert Keyword.get(opts, :remote_device_id) == 12
      assert Keyword.get(opts, :allow_numeric_constants) == true
      assert Keyword.get(opts, :object_opts) == [allow_numeric_constants: true]
    end

    test "passes skip mode through object_opts" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}

      value_opts = PropertyLoad.scan_read_opts(device_obj, :value)
      assert Keyword.get(value_opts, :allow_unknown_properties) == :no_unpack
      assert Keyword.get(value_opts, :remote_device_id) == 12
      assert Keyword.get(value_opts, :allow_numeric_constants) == true

      object_opts = Keyword.get(value_opts, :object_opts)
      assert Keyword.get(object_opts, :allow_numeric_constants) == true
      assert Keyword.get(object_opts, :skip_property_validation_remote_object) == :value

      all_opts = PropertyLoad.scan_read_opts(device_obj, true)
      all_object_opts = Keyword.get(all_opts, :object_opts)
      assert Keyword.get(all_object_opts, :allow_numeric_constants) == true
      assert Keyword.get(all_object_opts, :skip_property_validation_remote_object) == true
    end

    test "passes ignore_invalid_properties for ignore_invalid recovery mode" do
      device_obj = %ObjectIdentifier{type: :device, instance: 12}
      opts = PropertyLoad.scan_read_opts(device_obj, :ignore_invalid)

      assert Keyword.get(opts, :ignore_invalid_properties) == true

      refute Keyword.has_key?(
               Keyword.get(opts, :object_opts),
               :skip_property_validation_remote_object
             )
    end
  end
end
