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

  describe "read_all/3" do
    test "lists only properties reported by the BACnet object" do
      {:ok, object} = AnalogInput.create(1, "AI-1", %{present_value: 1.0, description: "test"})
      expected = PropertyReader.normalize_properties(ObjectsUtility.get_properties(object))

      assert {:ok, rows} =
               PropertyReader.read_all(
                 ObjectPropertiesClient,
                 :dest,
                 %ObjectIdentifier{type: :analog_input, instance: 1}
               )

      assert Enum.map(rows, & &1.property) |> Enum.sort() == Enum.sort(expected)
      assert Enum.find(rows, &(&1.property == :present_value)).value == 1.0
      assert Enum.all?(rows, &Map.has_key?(&1, :value_display))
    end

    test "does not crash when RPM returns object identifiers" do
      object = %ObjectIdentifier{type: :analog_input, instance: 197}

      assert {:ok, rows} = PropertyReader.read_all(MockClient, :dest, object)
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
  end

  defmodule UnavailableClient do
    def read_object(_destination, _object, _opts), do: {:error, :timeout}
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
