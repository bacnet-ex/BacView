defmodule BacView.BACnet.SinglePropertyReadTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.SinglePropertyRead
  alias BacView.Test.BacnetEtsLock

  @tables [{:bacview_devices, [:named_table, :set, :public]}]

  defmodule FakeClient do
    def read_property(destination, object, property, opts) do
      send(self(), {:read_property, destination, object, property, opts})
      {:ok, 21.5}
    end
  end

  defmodule RawRetryClient do
    def read_property(_dest, _object, _property, opts) do
      if Keyword.get(opts, :raw) do
        {:ok, :raw_value}
      else
        {:error, :unsupported_object_type}
      end
    end
  end

  setup do
    previous_probe = Application.get_env(:bacview, :device_iam_broadcast_probe)

    Application.put_env(:bacview, :device_iam_broadcast_probe, fn _id -> {:error, :no_iam} end)

    on_exit(fn ->
      restore_env(:device_iam_broadcast_probe, previous_probe)
    end)

    :ok
  end

  test "reads via discovered device id and forwards array index" do
    address = {{192, 168, 1, 10}, 47_808}
    object = %ObjectIdentifier{type: :analog_value, instance: 1}

    BacnetEtsLock.with_tables(@tables, fn ->
      :ets.insert(:bacview_devices, {42, %{id: 42, instance: 42, address: address}})

      assert {:ok, result} =
               SinglePropertyRead.run(
                 %{
                   destination: {:device_id, 42},
                   object: object,
                   property: :present_value,
                   array_index: 3
                 },
                 client: FakeClient
               )

      assert result.value == 21.5
      assert result.destination == address
      assert_received {:read_property, ^address, ^object, :present_value, opts}
      assert Keyword.get(opts, :array_index) == 3
    end)
  end

  test "reads via IPv4 address without discovery" do
    dest = {{10, 0, 0, 1}, 47_808}
    object = %ObjectIdentifier{type: :analog_input, instance: 2}

    assert {:ok, result} =
             SinglePropertyRead.run(
               %{
                 destination: {:address, dest},
                 object: object,
                 property: :object_name,
                 array_index: nil
               },
               client: FakeClient
             )

    assert result.destination == dest
    assert_received {:read_property, ^dest, ^object, :object_name, _opts}
  end

  test "reads via MS/TP MAC address" do
    object = %ObjectIdentifier{type: :binary_value, instance: 7}

    assert {:ok, _result} =
             SinglePropertyRead.run(
               %{
                 destination: {:address, 42},
                 object: object,
                 property: :present_value,
                 array_index: nil
               },
               client: FakeClient
             )

    assert_received {:read_property, 42, ^object, :present_value, _opts}
  end

  test "from_uri resolves device id and defaults present-value" do
    address = {{192, 168, 1, 10}, 47_808}

    BacnetEtsLock.with_tables(@tables, fn ->
      :ets.insert(:bacview_devices, {123, %{id: 123, instance: 123, address: address}})

      assert {:ok, result} =
               SinglePropertyRead.from_uri("bacnet://123/analog-value,5", client: FakeClient)

      assert result.object.type == :analog_value
      assert result.object.instance == 5
      assert result.property == :present_value
      assert_received {:read_property, ^address, object, :present_value, _opts}
      assert object.instance == 5
    end)
  end

  test "from_uri rejects file content URIs" do
    assert {:error, :file_content_uri} =
             SinglePropertyRead.from_uri("bacnet://5/file,10", client: FakeClient)
  end

  test "from_uri .this uses this_device_id" do
    address = {{10, 0, 0, 1}, 47_808}

    BacnetEtsLock.with_tables(@tables, fn ->
      :ets.insert(:bacview_devices, {9, %{id: 9, instance: 9, address: address}})

      assert {:ok, _result} =
               SinglePropertyRead.from_uri("bacnet://.this/analog-input,1",
                 client: FakeClient,
                 this_device_id: 9
               )

      assert_received {:read_property, ^address, _object, :present_value, _opts}
    end)
  end

  test "from_uri .this without current device errors" do
    assert {:error, :this_device_unknown} =
             SinglePropertyRead.from_uri("bacnet://.this/analog-input,1", client: FakeClient)
  end

  test "from_params uses form fields even when a URI is present" do
    params = %{
      "uri" => "bacnet://123/analog-value,5/present-value",
      "locator" => "address",
      "address" => "10.0.0.1",
      "object_type" => "binary-input",
      "instance" => "9",
      "property" => "object-name"
    }

    assert {:ok, result} =
             SinglePropertyRead.from_params(params, client: FakeClient, transport: "ipv4")

    assert result.destination == {{10, 0, 0, 1}, 47_808}
    assert result.object.type == :binary_input
    assert result.object.instance == 9
    assert result.property == :object_name
  end

  test "from_form IPv4 address path" do
    params = %{
      "locator" => "address",
      "address" => "10.0.0.1:47809",
      "object_type" => "analog-value",
      "instance" => "4",
      "property" => "present-value"
    }

    assert {:ok, result} =
             SinglePropertyRead.from_form(params, client: FakeClient, transport: "ipv4")

    assert result.destination == {{10, 0, 0, 1}, 47_809}
    assert_received {:read_property, {{10, 0, 0, 1}, 47_809}, object, :present_value, _opts}
    assert object.type == :analog_value
    assert object.instance == 4
  end

  test "from_form MS/TP address path" do
    params = %{
      "locator" => "address",
      "address" => "12",
      "object_type" => "binary-input",
      "instance" => "1",
      "property" => "present-value"
    }

    assert {:ok, result} =
             SinglePropertyRead.from_form(params, client: FakeClient, transport: "mstp")

    assert result.destination == 12
  end

  test "from_form defaults present-value when property is blank" do
    params = %{
      "locator" => "address",
      "address" => "10.0.0.1",
      "object_type" => "analog-input",
      "instance" => "1",
      "property" => ""
    }

    assert {:ok, result} =
             SinglePropertyRead.from_form(params, client: FakeClient, transport: "ipv4")

    assert result.property == :present_value
  end

  test "unknown device id returns error" do
    BacnetEtsLock.with_tables(@tables, fn ->
      assert {:error, :unknown_device} =
               SinglePropertyRead.run(
                 %{
                   destination: {:device_id, 99},
                   object: %ObjectIdentifier{type: :analog_value, instance: 1},
                   property: :present_value,
                   array_index: nil
                 },
                 client: FakeClient
               )
    end)
  end

  test "retries unsupported object types with raw: true" do
    assert {:ok, %{value: :raw_value}} =
             SinglePropertyRead.run(
               %{
                 destination: {:address, {{10, 0, 0, 1}, 47_808}},
                 object: %ObjectIdentifier{type: 900, instance: 1},
                 property: 512,
                 array_index: nil
               },
               client: RawRetryClient
             )
  end

  defp restore_env(key, nil), do: Application.delete_env(:bacview, key)
  defp restore_env(key, value), do: Application.put_env(:bacview, key, value)
end
