defmodule BacView.BACnet.PropertyLoadSkipResolveTest do
  @moduledoc """
  Verifies the ObjectLive path: recovery stores a skip mode, then
  `read_properties` without an explicit `skip_mode:` still builds relaxed
  Client opts (session resolves via ValidationSkipStore + PropertyLoad).
  """
  use ExUnit.Case, async: false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.PropertyLoad
  alias BacView.BACnet.ValidationSkipStore
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_validation_skip_modes, [:named_table, :set, :public, read_concurrency: true]}
  ]

  test "put skip mode then resolve without client skip_mode yields relaxed read opts" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 92_001
      object = %ObjectIdentifier{type: :multi_state_value, instance: 5}
      device_obj = %ObjectIdentifier{type: :device, instance: device_id}

      assert ValidationSkipStore.put(device_id, object, :value) == :ok

      # Session state after recovery may have empty untagged summaries in memory
      # while ETS still holds the durable mode (or ObjectLive omits skip_mode:).
      state = %{
        device_id: device_id,
        objects: [%{type: :multi_state_value, instance: 5}],
        device: %{object: device_obj, objects: []}
      }

      skip_mode = ValidationSkipStore.resolve(state, object)
      assert skip_mode == :value

      # DeviceSession.read_properties does: Keyword.get(opts, :skip_mode) || resolve(...)
      call_opts = []
      effective_skip = Keyword.get(call_opts, :skip_mode) || skip_mode
      assert effective_skip == :value

      read_opts = PropertyLoad.property_read_opts(effective_skip, device_obj)

      assert Keyword.get(read_opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]

      assert Keyword.get(read_opts, :remote_device_id) == device_id
      assert Keyword.get(read_opts, :allow_unknown_properties) == true

      # Skip mode also forces the scan-fallback property path for non-device objects.
      assert PropertyLoad.properties_scan_fallback_path?(object, effective_skip, device_obj)
    end)
  end

  test "nil skip mode keeps strict property read opts" do
    device_obj = %ObjectIdentifier{type: :device, instance: 12}
    object = %ObjectIdentifier{type: :analog_input, instance: 1}

    state = %{
      device_id: 12,
      objects: [%{type: :analog_input, instance: 1}],
      device: %{object: device_obj, objects: []}
    }

    assert ValidationSkipStore.resolve(state, object) == nil

    read_opts = PropertyLoad.property_read_opts(nil, device_obj)
    refute Keyword.has_key?(read_opts, :object_opts)
    refute PropertyLoad.properties_scan_fallback_path?(object, nil, device_obj)
  end
end
