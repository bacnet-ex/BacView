defmodule BacView.BACnet.ValidationSkipStoreTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.ValidationSkipStore
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_validation_skip_modes, [:named_table, :set, :public, read_concurrency: true]}
  ]

  test "put/get roundtrip and clear_device" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 91_001
      object = %ObjectIdentifier{type: :analog_input, instance: 3}
      other = %ObjectIdentifier{type: :binary_input, instance: 1}

      assert ValidationSkipStore.put(device_id, object, :value) == :ok
      assert ValidationSkipStore.put(device_id, other, true) == :ok
      assert ValidationSkipStore.get(device_id, object) == :value
      assert ValidationSkipStore.get(device_id, other) == true

      assert ValidationSkipStore.clear_device(device_id) == :ok
      assert ValidationSkipStore.get(device_id, object) == nil
      assert ValidationSkipStore.get(device_id, other) == nil
    end)
  end

  test "from_objects and apply_to_objects" do
    object_id = %ObjectIdentifier{type: :multi_state_value, instance: 42}

    objects = [
      %{type: :analog_input, instance: 1},
      %{type: :multi_state_value, instance: 42}
    ]

    assert ValidationSkipStore.from_objects(objects, object_id) == nil

    tagged = ValidationSkipStore.apply_to_objects(objects, object_id, :value)

    assert tagged == [
             %{type: :analog_input, instance: 1},
             %{type: :multi_state_value, instance: 42, property_validation_skip_mode: :value}
           ]

    assert ValidationSkipStore.from_objects(tagged, object_id) == :value
  end

  test "resolve prefers session object tags over ETS" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 91_002
      object = %ObjectIdentifier{type: :analog_input, instance: 7}

      ValidationSkipStore.put(device_id, object, true)

      state = %{
        device_id: device_id,
        objects: [
          %{type: :analog_input, instance: 7, property_validation_skip_mode: :value}
        ],
        device: %{objects: []}
      }

      assert ValidationSkipStore.resolve(state, object) == :value
    end)
  end

  test "resolve falls back to ETS when summaries have no tag" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_id = 91_003
      object = %ObjectIdentifier{type: :analog_input, instance: 8}

      ValidationSkipStore.put(device_id, object, :value)

      state = %{
        device_id: device_id,
        objects: [%{type: :analog_input, instance: 8}],
        device: %{objects: []}
      }

      assert ValidationSkipStore.resolve(state, object) == :value
    end)
  end

  test "put creates the table when missing and persists the mode" do
    BacnetEtsLock.with_tables(@tables, fn ->
      table = :bacview_validation_skip_modes
      :ets.delete(table)
      assert :ets.whereis(table) == :undefined

      device_id = 91_004
      object = %ObjectIdentifier{type: :analog_input, instance: 9}

      assert ValidationSkipStore.put(device_id, object, :value) == :ok
      assert :ets.whereis(table) != :undefined
      assert ValidationSkipStore.get(device_id, object) == :value
    end)
  end
end
