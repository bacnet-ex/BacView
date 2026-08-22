defmodule BacView.BACnet.Protocol.BacnetUriTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Protocol.BacnetUri

  test "parse/1 returns an error for incomplete URIs instead of raising" do
    assert {:error, :invalid_bacnet_uri} = BacnetUri.parse("bacnet:")
    assert {:error, :invalid_device} = BacnetUri.parse("bacnet://")
    assert {:error, :invalid_bacnet_uri} = BacnetUri.parse("bacnet")
    refute BacnetUri.valid_str?("bacnet:")
  end

  test "parse/1 delegates to bacstack and defaults present-value" do
    assert {:ok, uri} = BacnetUri.parse("bacnet://123/analog-value,5")
    assert uri.device_identifier == %ObjectIdentifier{type: :device, instance: 123}
    assert uri.object_identifier == %ObjectIdentifier{type: :analog_value, instance: 5}
    assert uri.property_identifier == :present_value
  end

  test "encode_object/2 builds an object-level numeric URI" do
    object = %ObjectIdentifier{type: :analog_value, instance: 5}

    assert {:ok, "bacnet://114705/2,5"} = BacnetUri.encode_object(114_705, object)
    assert {:ok, parsed} = BacnetUri.parse("bacnet://114705/2,5")
    assert parsed.object_identifier == object
  end

  test "encode_object/2 accepts integer proprietary types" do
    object = %ObjectIdentifier{type: 685, instance: 10}
    assert {:ok, "bacnet://5/685,10"} = BacnetUri.encode_object(5, object)
  end

  test "encode_property/3 appends the numeric property identifier" do
    object = %ObjectIdentifier{type: :analog_value, instance: 5}

    assert {:ok, "bacnet://114705/2,5/85"} =
             BacnetUri.encode_property(114_705, object, :present_value)

    assert {:ok, "bacnet://5/685,10/35920"} =
             BacnetUri.encode_property(5, %ObjectIdentifier{type: 685, instance: 10}, 35_920)
  end

  test "encode_object/2 rejects invalid instances" do
    object = %ObjectIdentifier{type: :analog_value, instance: 5}
    assert {:error, :invalid_data} = BacnetUri.encode_object(-1, object)
  end

  test "property_for_read/1 errors for file content URIs" do
    assert {:ok, uri} = BacnetUri.parse("bacnet://5/file,10")
    assert {:error, :file_content_uri} = BacnetUri.property_for_read(uri)

    assert {:ok, sized} = BacnetUri.parse("bacnet://5/file,10/file-size")
    assert {:ok, :file_size} = BacnetUri.property_for_read(sized)
  end

  test "device_instance/2 resolves .this from the current page" do
    assert {:ok, uri} = BacnetUri.parse("bacnet://.this/analog-value,1")
    assert {:ok, 42} = BacnetUri.device_instance(uri, 42)
    assert {:error, :this_device_unknown} = BacnetUri.device_instance(uri, nil)
  end

  test "object_type_options/0 includes hyphenated standard names" do
    options = BacnetUri.object_type_options()
    assert "analog-value" in options
    assert "device" in options
  end
end
