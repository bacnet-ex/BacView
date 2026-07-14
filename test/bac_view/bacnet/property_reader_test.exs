defmodule BacView.BACnet.Protocol.PropertyReaderTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    ObjectIdentifier,
    ObjectTypes.AnalogInput,
    ObjectTypes.AnalogOutput,
    ObjectsUtility
  }

  alias BacView.BACnet.Protocol.PropertyReader

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

      assert_receive {:read_property_multiple_opts, rpm_opts}

      assert Keyword.get(rpm_opts, :object_opts) == [
               skip_property_validation_remote_object: :value
             ]
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

    test "falls back to individual reads when buffer overflow occurs" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, %{properties: rows, unknown_properties: []}} =
               PropertyReader.read_all(__MODULE__.BufferOverflowClient, :dest, object)

      assert expected_fallback_rows(rows)
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
    test "includes every property from the list even when not read" do
      rows =
        PropertyReader.format_property_rows(
          [:object_name, :present_value, :description],
          %{object_name: "AO-1"}
        )

      assert length(rows) == 3
      assert Enum.find(rows, &(&1.property == :description)).value == nil
      assert Enum.find(rows, &(&1.property == :description)).value_formatted == "—"
    end

    test "labels unknown numeric property ids" do
      [row] = PropertyReader.format_property_rows([512], %{512 => 42})

      assert row.property_name == "property 512"
      assert row.value == 42
    end
  end

  describe "format_unknown_properties/1" do
    test "formats numeric and atom identifiers from _unknown_properties" do
      {:ok, object} =
        AnalogInput.create(
          1,
          "AI-1",
          Map.merge(%{present_value: 1.0, vendor_prop: "x"}, %{512 => 42}),
          allow_unknown_properties: true,
          remote_object: 1555
        )

      rows = PropertyReader.format_unknown_properties(object)

      assert length(rows) == 2

      assert %{property: 512, property_name: "property 512", value: 42} =
               Enum.find(rows, &(&1.property == 512))

      assert %{
               property: :vendor_prop,
               property_name: "vendor prop",
               value: "x",
               string_value?: true,
               raw_binary: "x"
             } =
               Enum.find(rows, &(&1.property == :vendor_prop))

      refute Enum.find(rows, &(&1.property == 512)).string_value?

      assert Enum.all?(rows, &Map.has_key?(&1, :value_display))
      assert Enum.all?(rows, &Map.has_key?(&1, :type))
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
      assert row.value_formatted == "Normal"
    end
  end
end
