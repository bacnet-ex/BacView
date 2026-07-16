defmodule BacView.BACnet.Protocol.PropertyReaderTest do
  use ExUnit.Case, async: true

  require Logger

  alias BACnet.Protocol.{
    ObjectIdentifier,
    ObjectTypes.AnalogInput,
    ObjectTypes.AnalogOutput,
    ObjectTypes.IntegerValue,
    ObjectsUtility
  }

  alias BacView.BACnet.Client
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.Test.{BacnetEtsLock, SilenceLogger}

  setup do
    SilenceLogger.silence_for_test(Client, :error)
    :ok
  end

  defmodule MockClient do
    def read_object(_destination, _object, _opts) do
      {:ok, object} = AnalogInput.create(197, "AI-197", %{present_value: 42.0})
      {:ok, object}
    end

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:ok, %ObjectIdentifier{type: :analog_input, instance: 197}}

    def read_property(_destination, _object, property, _opts),
      do: {:ok, Map.get(%{object_name: "AI-197", present_value: 42.0}, property)}
  end

  describe "normalize_properties/1" do
    test "maps engineering_units alias to units" do
      assert PropertyReader.normalize_properties([:engineering_units]) == [:units]
    end

    test "drops unknown property identifiers" do
      assert PropertyReader.normalize_properties([:engineering_units, :bogus_property]) == [
               :units
             ]
    end

    test "keeps valid BACnet properties" do
      props = PropertyReader.normalize_properties([:object_name, :present_value, :description])

      assert :object_name in props
      assert :present_value in props
      assert :description in props
    end

    test "deduplicates after normalization" do
      assert PropertyReader.normalize_properties([:units, :engineering_units]) == [:units]
    end

    test "keeps vendor-specific numeric property identifiers" do
      assert PropertyReader.normalize_properties([:present_value, 512]) == [
               :present_value,
               512
             ]
    end

    test "returns empty list for non-list input" do
      assert PropertyReader.normalize_properties(%ObjectIdentifier{
               type: :analog_input,
               instance: 1
             }) ==
               []
    end

    test "drops object identifiers embedded in property lists" do
      oid = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert PropertyReader.normalize_properties([:present_value, oid]) == [:present_value]
    end
  end

  defmodule ObjectPropertiesClient do
    @object (
              {:ok, object} =
                AnalogInput.create(1, "AI-1", %{present_value: 1.0, description: "test"})

              object
            )

    def read_object(_destination, _object, _opts), do: {:ok, @object}

    def read_property_multiple(_destination, _object, properties, _opts) do
      known = %{
        object_name: "AI-1",
        present_value: 1.0,
        description: "test"
      }

      values = Map.new(properties, fn prop -> {prop, Map.get(known, prop)} end)
      {:ok, values}
    end

    def read_property(_destination, _object, _property, _opts), do: {:error, :skipped}
  end

  defmodule OptsCapturingClient do
    @object (
              {:ok, object} =
                AnalogInput.create(1, "AI-1", %{present_value: 1.0, description: "test"})

              object
            )

    def read_object(_destination, _object, opts) do
      send(self(), {:read_object_opts, opts})
      {:ok, @object}
    end

    def read_property_multiple(_destination, _object, properties, opts) do
      send(self(), {:read_property_multiple_opts, opts})

      known = %{
        object_name: "AI-1",
        present_value: 1.0,
        description: "test"
      }

      values = Map.new(properties, fn prop -> {prop, Map.get(known, prop)} end)
      {:ok, values}
    end

    def read_property(_destination, _object, _property, _opts), do: {:error, :skipped}
  end

  describe "read_result_from_object/2" do
    test "formats BACnet object structs into property rows" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{present_value: 1.0, description: "test"})
      object_id = %ObjectIdentifier{type: :analog_input, instance: 1}

      result = PropertyReader.read_result_from_object(object_id, object)

      assert %{properties: rows, unknown_properties: []} = result
      assert Enum.any?(rows, &(&1.property == :present_value and &1.value == 1.0))
    end

    test "formats plain scan maps into property rows" do
      object_id = %ObjectIdentifier{type: :analog_input, instance: 1}

      result =
        PropertyReader.read_result_from_object(object_id, %{
          object_name: "AI-1",
          present_value: 1.0
        })

      assert %{properties: rows, unknown_properties: []} = result
      assert Enum.any?(rows, &(&1.property == :present_value and &1.value == 1.0))
    end

    test "labels integer properties from object schema" do
      {:ok, unsigned_object} =
        AnalogInput.create(1, "AI-1", %{present_value: 1.0, update_interval: 30})

      {:ok, signed_object} = IntegerValue.create(1, "IV-1", %{present_value: -5})

      unsigned_id = %ObjectIdentifier{type: :analog_input, instance: 1}
      signed_id = %ObjectIdentifier{type: :integer_value, instance: 1}

      unsigned_rows =
        PropertyReader.read_result_from_object(unsigned_id, unsigned_object).properties

      signed_rows = PropertyReader.read_result_from_object(signed_id, signed_object).properties

      assert Enum.find(unsigned_rows, &(&1.property == :update_interval)).type ==
               "UNSIGNED INTEGER"

      assert Enum.find(signed_rows, &(&1.property == :present_value)).type == "SIGNED INTEGER"
    end
  end

  describe "read_all/3" do
    test "lists only properties reported by the BACnet object" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{present_value: 1.0, description: "test"})
      expected = PropertyReader.normalize_properties(ObjectsUtility.get_properties(object))

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(
                 ObjectPropertiesClient,
                 :dest,
                 %ObjectIdentifier{type: :analog_input, instance: 1}
               )

      assert Enum.map(rows, & &1.property) |> Enum.sort() == Enum.sort(expected)
      assert Enum.find(rows, &(&1.property == :present_value)).value == 1.0
      assert Enum.all?(rows, &Map.has_key?(&1, :value_display))
    end

    test "passes object_opts through to BACnet reads" do
      object = %ObjectIdentifier{type: :analog_input, instance: 1}

      assert {:ok, %{properties: _rows, unknown_properties: []}} =
               PropertyReader.read_all(
                 OptsCapturingClient,
                 :dest,
                 object,
                 object_opts: [skip_property_validation_remote_object: :value]
               )

      assert_receive {:read_object_opts, read_object_opts}

      assert Keyword.get(read_object_opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]

      refute_receive {:read_property_multiple_opts, _opts}
    end

    test "does not re-read properties after successful read_object" do
      object = %ObjectIdentifier{type: :analog_input, instance: 1}

      assert {:ok, %{properties: rows}} =
               PropertyReader.read_all(OptsCapturingClient, :dest, object)

      assert Enum.any?(rows, &(&1.property == :present_value))
      refute_receive {:read_property_multiple_opts, _opts}
      refute_receive {:read_property, _opts}
    end

    test "does not crash when RPM returns object identifiers" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(MockClient, :dest, object)

      assert is_list(rows)
      assert Enum.all?(rows, &is_map/1)
      {:ok, loaded} = AnalogInput.create(197, "AI-197", %{present_value: 42.0})

      expected =
        loaded
        |> ObjectsUtility.get_properties()
        |> PropertyReader.normalize_properties()

      assert Enum.map(rows, & &1.property) |> Enum.sort() == Enum.sort(expected)
    end

    test "returns error when object cannot be read" do
      assert {:error, :timeout} =
               PropertyReader.read_all(
                 __MODULE__.UnavailableClient,
                 :dest,
                 %ObjectIdentifier{type: :analog_input, instance: 1}
               )
    end

    test "falls back to individual reads when segmentation is not supported" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(__MODULE__.SegmentationClient, :dest, object)

      assert expected_fallback_rows(rows)
    end

    test "reports progress during individual property reads" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}
      parent = self()

      assert {:ok, %{properties: rows}} =
               PropertyReader.read_all(
                 __MODULE__.SegmentationClient,
                 :dest,
                 object,
                 on_property_progress: fn progress ->
                   send(parent, {:progress, progress})
                 end
               )

      assert expected_fallback_rows(rows)

      progresses = drain_progress_messages()
      assert Enum.any?(progresses, &(&1.done == 0 and &1.total > 0))
      assert Enum.any?(progresses, &(&1.done == &1.total and &1.total > 0))
      assert Enum.all?(progresses, &(&1.stage == :reading_properties))
    end

    test "falls back to individual reads when buffer overflow occurs" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(__MODULE__.BufferOverflowClient, :dest, object)

      assert expected_fallback_rows(rows)
    end

    test "falls back to individual reads when RPM is unrecognized" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(__MODULE__.UnrecognizedServiceClient, :dest, object)

      assert expected_fallback_rows(rows)
    end

    test "reads property_list by index when the full array read fails" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(__MODULE__.PropertyListIndexedOnlyClient, :dest, object)

      assert expected_fallback_rows(rows)
    end

    test "falls back to object schema when property_list is unavailable" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(
                 __MODULE__.PropertyListUnavailableClient,
                 :dest,
                 object
               )

      properties = Enum.map(rows, & &1.property)

      assert :object_name in properties
      assert :present_value in properties
      assert :description in properties
      refute :property_list in properties
    end

    test "drops schema properties that failed to read on the individual path" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows}} =
               PropertyReader.read_all(
                 __MODULE__.PropertyListUnavailableClient,
                 :dest,
                 object
               )

      properties = Enum.map(rows, & &1.property)

      assert properties == [
               :description,
               :event_state,
               :object_name,
               :out_of_service,
               :present_value,
               :status_flags,
               :units
             ]

      refute Enum.any?(rows, &is_nil(&1.value))
    end

    test "casts a remote object after individual schema reads without inventing unread rows" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(
                 __MODULE__.PropertyListUnavailableClient,
                 :dest,
                 object,
                 remote_device_id: 42,
                 object_opts: [skip_property_validation_remote_object: true]
               )

      properties = Enum.map(rows, & &1.property) |> Enum.sort()

      assert properties == [
               :description,
               :event_state,
               :object_name,
               :out_of_service,
               :present_value,
               :status_flags,
               :units
             ]

      refute Enum.any?(rows, &is_nil(&1.value))

      assert {:ok, schema} = PropertyReader.schema_properties(object)
      assert length(properties) < length(schema)

      present_value = Enum.find(rows, &(&1.property == :present_value))
      assert present_value.value == 42.0
      assert is_binary(present_value.type)
    end

    test "emits debug logs for individual schema fallback reads" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}
      previous_level = Logger.level()
      previous_flag = Application.get_env(:bacview, :debug_log_property_reader)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Logger.configure(level: :debug)

          try do
            Application.put_env(:bacview, :debug_log_property_reader, true)

            PropertyReader.read_all(
              __MODULE__.PropertyListUnavailableClient,
              :dest,
              object,
              remote_device_id: 42,
              object_opts: [skip_property_validation_remote_object: true]
            )
          after
            Application.put_env(:bacview, :debug_log_property_reader, previous_flag)
            Logger.configure(level: previous_level)
          end
        end)

      assert log =~ "PropertyReader analog_input:197"
      assert log =~ "read_all_start"
      assert log =~ "fetch_bacnet_object"
      assert log =~ "property_identifiers"
      assert log =~ "schema_fallback"
      assert log =~ "individual_reads_done"
      assert log =~ "read_all_done"
      assert log =~ "individual_cast_failed" or log =~ "individual_cast_ok"
    end

    test "does not index property_list when full array fails with unknown_property" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}
      __MODULE__.PropertyListUnknownNoIndexClient.reset()

      assert {:ok, %{properties: rows}} =
               PropertyReader.read_all(
                 __MODULE__.PropertyListUnknownNoIndexClient,
                 :dest,
                 object
               )

      assert :present_value in Enum.map(rows, & &1.property)
      assert __MODULE__.PropertyListUnknownNoIndexClient.indexed_count() == 0
    end

    test "reads device object from schema when property_list is unavailable" do
      object = %ObjectIdentifier{type: :device, instance: 100_111}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(
                 __MODULE__.PropertyListUnavailableDeviceClient,
                 :dest,
                 object
               )

      properties = Enum.map(rows, & &1.property)

      assert Enum.sort(properties) == [
               :application_software_version,
               :firmware_revision,
               :max_apdu_length_accepted,
               :model_name,
               :object_name,
               :protocol_revision,
               :protocol_version,
               :segmentation_supported,
               :vendor_name
             ]

      refute :object_list in properties
      refute :property_list in properties
      refute Enum.any?(rows, &is_nil(&1.value))
    end

    test "reads device metadata without object_list during schema fallback" do
      object = %ObjectIdentifier{type: :device, instance: 100_111}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(
                 __MODULE__.DeviceObjectListIndexedClient,
                 :dest,
                 object
               )

      properties = Enum.map(rows, & &1.property)

      assert :vendor_name in properties
      assert :model_name in properties
      refute :object_list in properties
    end
  end

  describe "property_read_concurrency/1" do
    test "uses per-device max_concurrency when set" do
      BacnetEtsLock.with_tables([:bacview_devices], fn ->
        if :ets.whereis(:bacview_devices) == :undefined do
          :ets.new(:bacview_devices, [:named_table, :set, :public])
        else
          :ets.delete_all_objects(:bacview_devices)
        end

        :ets.insert(:bacview_devices, {42, %{id: 42, max_concurrency: 1}})

        assert PropertyReader.property_read_concurrency(device_id: 42) == 1
        assert PropertyReader.property_read_concurrency(remote_device_id: 42) == 1
      end)
    end

    test "defaults to historical healthy concurrency of 8" do
      previous = Application.get_env(:bacview, :property_read_concurrency)

      try do
        Application.delete_env(:bacview, :property_read_concurrency)
        assert PropertyReader.property_read_concurrency() == 8
      after
        restore_property_read_concurrency(previous)
      end
    end

    test "reads positive concurrency from application env" do
      previous = Application.get_env(:bacview, :property_read_concurrency)

      try do
        Application.put_env(:bacview, :property_read_concurrency, 1)
        assert PropertyReader.property_read_concurrency() == 1

        Application.put_env(:bacview, :property_read_concurrency, 0)
        assert PropertyReader.property_read_concurrency() == 8
      after
        restore_property_read_concurrency(previous)
      end
    end
  end

  describe "schema_properties/1" do
    test "returns BACnet object definition properties for device" do
      object = %ObjectIdentifier{type: :device, instance: 1}

      assert {:ok, props} = PropertyReader.schema_properties(object)

      assert :object_name in props
      assert :vendor_name in props
      assert :object_list in props
      refute :property_list in props
      assert length(props) >= 50
      refute :engineering_units in props
    end

    test "returns error for unsupported object types" do
      assert {:error, :unsupported_object_type} =
               PropertyReader.schema_properties(%ObjectIdentifier{
                 type: :invalid_type,
                 instance: 1
               })
    end
  end

  describe "skip_heavy_properties/2" do
    test "drops large device properties from schema reads" do
      object = %ObjectIdentifier{type: :device, instance: 1}
      props = [:object_name, :object_list, :vendor_name, :active_cov_subscriptions]

      assert PropertyReader.skip_heavy_properties(props, object) == [:object_name, :vendor_name]
    end

    test "still drops property_list for non-device objects" do
      object = %ObjectIdentifier{type: :analog_input, instance: 1}
      props = [:object_name, :property_list, :present_value]

      assert PropertyReader.skip_heavy_properties(props, object) == [:object_name, :present_value]
    end
  end

  describe "read_property_value/5" do
    test "accepts raw value when bacstack rejects decoded description" do
      object = %ObjectIdentifier{type: :device, instance: 1}
      raw = "Kältemaschine 1"

      assert {:ok, ^raw} =
               PropertyReader.read_property_value(
                 __MODULE__.InvalidDescriptionClient,
                 :dest,
                 object,
                 :description,
                 []
               )
    end

    test "sanitizes Latin-1 description bytes for JSON serialization" do
      object = %ObjectIdentifier{type: :device, instance: 1}

      assert {:ok, sanitized} =
               PropertyReader.read_property_value(
                 __MODULE__.Latin1DescriptionClient,
                 :dest,
                 object,
                 :description,
                 []
               )

      assert sanitized == "Kältemaschine 1 / RHOSS FP ECO-E VFD TCAITE 1325 RH00376802"
      assert String.valid?(sanitized)
      assert Jason.encode!(sanitized)
    end

    test "reads array properties by index on segmentation errors" do
      object = %ObjectIdentifier{type: :device, instance: 100_111}

      assert {:ok, [%ObjectIdentifier{type: :device, instance: 100_111}]} =
               PropertyReader.read_property_value(
                 __MODULE__.DeviceObjectListIndexedClient,
                 :dest,
                 object,
                 :object_list,
                 []
               )
    end
  end

  describe "array_property?/2" do
    test "detects array properties from object type definition" do
      object = %ObjectIdentifier{type: :device, instance: 1}

      assert PropertyReader.array_property?(object, :object_list)
      refute PropertyReader.array_property?(object, :vendor_name)
    end
  end

  defp expected_fallback_rows(rows) do
    properties = Enum.map(rows, & &1.property)

    assert :present_value in properties
    assert :description in properties
    assert :object_name in properties
    refute :property_list in properties

    assert Enum.find(rows, &(&1.property == :present_value)).value == 42.0
    assert Enum.find(rows, &(&1.property == :description)).value == "test input"
  end

  defmodule UnavailableClient do
    def read_object(_destination, _object, _opts), do: {:error, :timeout}
  end

  defmodule UnrecognizedServiceClient do
    alias BACnet.Protocol.APDU

    @property_list [
      :object_identifier,
      :object_name,
      :object_type,
      :present_value,
      :description,
      :status_flags,
      :event_state,
      :out_of_service,
      :units
    ]

    @rpm_reject {:error,
                 {:bacnet_reject, %APDU.Reject{invoke_id: 1, reason: :unrecognized_service}}}

    def read_object(_destination, _object, _opts), do: @rpm_reject

    def read_property_multiple(_destination, _object, _properties, _opts), do: @rpm_reject

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "AI-197"}

    def read_property(_destination, _object, :property_list, opts) do
      case Keyword.get(opts, :array_index) do
        nil -> {:ok, @property_list}
        0 -> {:ok, length(@property_list)}
        idx when is_integer(idx) -> {:ok, Enum.at(@property_list, idx - 1)}
      end
    end

    def read_property(_destination, _object, property, _opts) do
      values = %{
        present_value: 42.0,
        description: "test input",
        status_flags: [false, false, false, false],
        event_state: :normal,
        out_of_service: false,
        units: :degrees_celsius
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :property_not_found}
      end
    end
  end

  defmodule BufferOverflowClient do
    @property_list [
      :object_identifier,
      :object_name,
      :object_type,
      :present_value,
      :description,
      :status_flags,
      :event_state,
      :out_of_service,
      :units
    ]

    def read_object(_destination, _object, _opts), do: {:error, :buffer_overflow}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :buffer_overflow}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "AI-197"}

    def read_property(_destination, _object, :property_list, opts) do
      case Keyword.get(opts, :array_index) do
        nil -> {:ok, @property_list}
        0 -> {:ok, length(@property_list)}
        idx when is_integer(idx) -> {:ok, Enum.at(@property_list, idx - 1)}
      end
    end

    def read_property(_destination, _object, property, _opts) do
      values = %{
        present_value: 42.0,
        description: "test input",
        status_flags: [false, false, false, false],
        event_state: :normal,
        out_of_service: false,
        units: :degrees_celsius
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :property_not_found}
      end
    end
  end

  defmodule PropertyListIndexedOnlyClient do
    @property_list [
      :object_identifier,
      :object_name,
      :object_type,
      :present_value,
      :description,
      :status_flags,
      :event_state,
      :out_of_service,
      :units
    ]

    def read_object(_destination, _object, _opts), do: {:error, :segmentation_not_supported}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :segmentation_not_supported}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "AI-197"}

    def read_property(_destination, _object, :property_list, opts) do
      case Keyword.get(opts, :array_index) do
        nil -> {:error, :property_not_readable}
        0 -> {:ok, length(@property_list)}
        idx when is_integer(idx) -> {:ok, Enum.at(@property_list, idx - 1)}
      end
    end

    def read_property(_destination, _object, property, _opts) do
      values = %{
        present_value: 42.0,
        description: "test input",
        status_flags: [false, false, false, false],
        event_state: :normal,
        out_of_service: false,
        units: :degrees_celsius
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :property_not_found}
      end
    end
  end

  defmodule InvalidDescriptionClient do
    def read_property(_destination, _object, :description, _opts),
      do: {:error, {:invalid_property_value, {:description, "Kältemaschine 1"}}}
  end

  defmodule Latin1DescriptionClient do
    def read_property(_destination, _object, :description, _opts) do
      latin1 = <<"K\xE4ltemaschine 1 / RHOSS FP ECO-E VFD TCAITE 1325 RH00376802">>
      {:error, {:invalid_property_value, {:description, latin1}}}
    end
  end

  defmodule PropertyListUnavailableClient do
    def read_object(_destination, _object, _opts), do: {:error, :segmentation_not_supported}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :segmentation_not_supported}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "AI-197"}

    def read_property(_destination, _object, :property_list, _opts),
      do: {:error, :unknown_property}

    def read_property(_destination, _object, property, _opts) do
      values = %{
        present_value: 42.0,
        description: "test input",
        status_flags: [false, false, false, false],
        event_state: :normal,
        out_of_service: false,
        units: :degrees_celsius
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :unknown_property}
      end
    end
  end

  defmodule PropertyListUnknownNoIndexClient do
    @table :bacview_property_list_index_probe

    def reset do
      ensure_table()
      :ets.insert(@table, {:indexed, 0})
      :ok
    end

    def indexed_count do
      ensure_table()

      case :ets.lookup(@table, :indexed) do
        [{:indexed, n}] -> n
        [] -> 0
      end
    end

    def read_object(_destination, _object, _opts), do: {:error, :segmentation_not_supported}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :segmentation_not_supported}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "AI-197"}

    def read_property(_destination, _object, :property_list, opts) do
      case Keyword.get(opts, :array_index) do
        nil ->
          {:error, :unknown_property}

        _index ->
          bump_indexed()
          {:error, :unknown_property}
      end
    end

    def read_property(_destination, _object, property, _opts) do
      values = %{
        present_value: 42.0,
        description: "test input",
        status_flags: [false, false, false, false],
        event_state: :normal,
        out_of_service: false,
        units: :degrees_celsius
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :unknown_property}
      end
    end

    defp bump_indexed do
      ensure_table()

      case :ets.lookup(@table, :indexed) do
        [{:indexed, n}] -> :ets.insert(@table, {:indexed, n + 1})
        [] -> :ets.insert(@table, {:indexed, 1})
      end
    end

    defp ensure_table do
      if :ets.whereis(@table) == :undefined do
        :ets.new(@table, [:named_table, :public, :set])
      end

      :ok
    end
  end

  defp restore_property_read_concurrency(nil),
    do: Application.delete_env(:bacview, :property_read_concurrency)

  defp restore_property_read_concurrency(value),
    do: Application.put_env(:bacview, :property_read_concurrency, value)

  defp drain_progress_messages(acc \\ []) do
    receive do
      {:progress, progress} -> drain_progress_messages([progress | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defmodule PropertyListUnavailableDeviceClient do
    def read_object(_destination, _object, _opts), do: {:error, :segmentation_not_supported}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :segmentation_not_supported}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "Device-100111"}

    def read_property(_destination, _object, :property_list, _opts),
      do: {:error, :unknown_property}

    def read_property(_destination, _object, property, _opts) do
      values = %{
        vendor_name: "Test Vendor",
        model_name: "Test Model",
        firmware_revision: "1.0",
        application_software_version: "2.0",
        protocol_version: 1,
        protocol_revision: 14,
        max_apdu_length_accepted: 480,
        segmentation_supported: :no_segmentation,
        object_list: [%ObjectIdentifier{type: :device, instance: 100_111}]
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :unknown_property}
      end
    end
  end

  defmodule DeviceObjectListIndexedClient do
    def read_object(_destination, _object, _opts), do: {:error, :segmentation_not_supported}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :segmentation_not_supported}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "Device-100111"}

    def read_property(_destination, _object, :property_list, _opts),
      do: {:error, :unknown_property}

    def read_property(_destination, _object, :object_list, opts) do
      case Keyword.get(opts, :array_index) do
        nil -> {:error, :segmentation_not_supported}
        0 -> {:ok, 1}
        1 -> {:ok, %ObjectIdentifier{type: :device, instance: 100_111}}
      end
    end

    def read_property(_destination, _object, property, _opts) do
      values = %{
        vendor_name: "Test Vendor",
        model_name: "Test Model"
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :unknown_property}
      end
    end
  end

  defmodule SegmentationClient do
    @property_list [
      :object_identifier,
      :object_name,
      :object_type,
      :present_value,
      :description,
      :status_flags,
      :event_state,
      :out_of_service,
      :units
    ]

    def read_object(_destination, _object, _opts), do: {:error, :segmentation_not_supported}

    def read_property_multiple(_destination, _object, _properties, _opts),
      do: {:error, :segmentation_not_supported}

    def read_property(_destination, _object, :object_name, _opts), do: {:ok, "AI-197"}

    def read_property(_destination, _object, :property_list, opts) do
      case Keyword.get(opts, :array_index) do
        nil -> {:ok, @property_list}
        0 -> {:ok, length(@property_list)}
        idx when is_integer(idx) -> {:ok, Enum.at(@property_list, idx - 1)}
      end
    end

    def read_property(_destination, _object, property, _opts) do
      values = %{
        present_value: 42.0,
        description: "test input",
        status_flags: [false, false, false, false],
        event_state: :normal,
        out_of_service: false,
        units: :degrees_celsius
      }

      case Map.fetch(values, property) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :property_not_found}
      end
    end
  end

  describe "format_property_rows/2" do
    test "formats nil values when caller still includes unread properties" do
      rows =
        PropertyReader.format_property_rows(
          [:object_name, :present_value, :description],
          %{object_name: "AO-1"}
        )

      assert length(rows) == 3
      assert Enum.find(rows, &(&1.property == :description)).value == nil
      assert Enum.find(rows, &(&1.property == :description)).value_formatted == "-"
    end

    test "labels unknown numeric property ids" do
      [row] = PropertyReader.format_property_rows([512], %{512 => 42})

      assert row.property_name == "property 512"
      assert row.value == 42
    end
  end

  describe "format_unknown_properties/1" do
    test "formats Encoding values from _unknown_properties" do
      integer_encoding = %BACnet.Protocol.ApplicationTags.Encoding{
        encoding: :primitive,
        type: :unsigned_integer,
        value: 42,
        extras: []
      }

      string_encoding = %BACnet.Protocol.ApplicationTags.Encoding{
        encoding: :primitive,
        type: :character_string,
        value: "x",
        extras: []
      }

      {:ok, object} =
        AnalogInput.create(1, "AI-1", %{present_value: 1.0}, remote_object: 1555)

      object = %{
        object
        | _unknown_properties: %{512 => integer_encoding, vendor_prop: string_encoding}
      }

      rows = PropertyReader.format_unknown_properties(object)

      assert length(rows) == 2

      assert %{
               property: 512,
               property_name: "property 512",
               value: ^integer_encoding,
               type: "UNSIGNED INTEGER",
               value_formatted: "42"
             } = Enum.find(rows, &(&1.property == 512))

      assert %{
               property: :vendor_prop,
               property_name: "vendor prop",
               value: ^string_encoding,
               type: "CHARACTER STRING",
               value_formatted: "x",
               string_value?: true,
               hex_toggle?: false,
               raw_binary: "x"
             } = Enum.find(rows, &(&1.property == :vendor_prop))

      refute Enum.find(rows, &(&1.property == 512)).string_value?

      assert Enum.all?(rows, &Map.has_key?(&1, :value_display))
    end

    test "labels Encoding lists in unknown properties as PROPRIETARY hex dumps" do
      encoding_list = [
        %BACnet.Protocol.ApplicationTags.Encoding{
          encoding: :primitive,
          type: :unsigned_integer,
          value: 3,
          extras: []
        },
        %BACnet.Protocol.ApplicationTags.Encoding{
          encoding: :primitive,
          type: :real,
          value: 21.5,
          extras: []
        }
      ]

      {:ok, object} =
        AnalogInput.create(1, "AI-1", %{present_value: 1.0}, remote_object: 1555)

      object = %{object | _unknown_properties: %{vendor_blob: encoding_list}}

      [row] = PropertyReader.format_unknown_properties(object)

      assert row.property == :vendor_blob
      assert row.type == "PROPRIETARY"
      assert row.string_value?
      refute row.hex_toggle?
      assert row.value_formatted =~ ":"
      refute row.value_formatted =~ "21.5"
    end

    test "returns empty list when no unknown properties are present" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{present_value: 1.0})
      assert PropertyReader.format_unknown_properties(object) == []
    end
  end

  describe "format_property_rows/2 writable and enrichment" do
    test "uses bac_type for boolean properties with nil value" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{})

      [row] =
        PropertyReader.format_property_rows(
          [:out_of_service],
          %{out_of_service: nil},
          object
        )

      assert row.bac_type == :boolean
      assert row.type == "BOOLEAN"
    end

    test "input present_value is read-only unless out of service is true" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{out_of_service: false, present_value: 21.0})

      rows =
        PropertyReader.format_property_rows(
          [:out_of_service, :present_value],
          %{out_of_service: false, present_value: 21.0},
          object
        )

      assert %{property: :out_of_service, writable: true, value: false} =
               Enum.find(rows, &(&1.property == :out_of_service))

      assert %{property: :present_value, writable: false} =
               Enum.find(rows, &(&1.property == :present_value))

      [oos_row, pv_row] =
        PropertyReader.format_property_rows(
          [:out_of_service, :present_value],
          %{out_of_service: true, present_value: 21.0},
          object
        )

      assert oos_row.writable
      assert oos_row.value == true
      assert pv_row.writable
    end

    test "output present_value writable flag still follows bacstack rules before enrich" do
      {:ok, object} =
        AnalogOutput.create(1, "AO-1", %{out_of_service: false, present_value: 21.0})

      [pv_row] =
        PropertyReader.format_property_rows(
          [:present_value],
          %{present_value: 21.0},
          object
        )

      refute pv_row.writable
    end

    test "enriches constant enumeration properties from the BACnet object" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{})

      [row] =
        PropertyReader.format_property_rows(
          [:event_state],
          %{event_state: :normal},
          object
        )

      assert row.enum_type == :event_state
      assert row.type == "ENUMERATED"
      assert length(row.enum_options) > 0
      assert row.value_formatted == "Normal (0)"
    end
  end
end
