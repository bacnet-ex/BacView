defmodule BacView.BACnet.RequestOptsTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.NpciTarget
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.IAm
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.RequestOpts
  alias BacView.Test.BacnetEtsLock

  @table :bacview_devices
  @address {{10, 0, 0, 5}, 47_808}

  setup do
    BacnetEtsLock.with_tables([@table], fn ->
      if :ets.whereis(@table) == :undefined do
        :ets.new(@table, [:named_table, :set, :public])
      else
        :ets.delete_all_objects(@table)
      end

      :ok
    end)
  end

  defp iam(instance) do
    %IAm{
      device: %ObjectIdentifier{type: :device, instance: instance},
      max_apdu: 1476,
      segmentation_supported: :segmented_both,
      vendor_id: 999
    }
  end

  defp store(instance, npci_source \\ nil) do
    Discovery.upsert_iam_device(iam(instance), @address, npci_source)
  end

  test "shared_address? is false for a single device at an address" do
    store(100)

    refute RequestOpts.shared_address?(@address)
  end

  test "shared_address? is true when multiple devices share an address" do
    store(100)
    store(200)

    assert RequestOpts.shared_address?(@address)
  end

  test "merge leaves opts unchanged for a unique address" do
    store(100)

    assert RequestOpts.merge(device_id: 100) == [device_id: 100]
  end

  test "merge adds npci destination but not invoke device_id on shared addresses" do
    npci_source = %NpciTarget{net: 3, address: 200}

    store(100)
    store(200, npci_source)

    merged = RequestOpts.merge(remote_device_id: 200)
    assert merged[:remote_device_id] == 200
    assert merged[:destination] == npci_source
    refute Keyword.has_key?(merged, :device_id)
  end

  test "merge adds npci destination for a routed device at a unique address" do
    npci_source = %NpciTarget{net: 3, address: 200}

    store(200, npci_source)

    merged = RequestOpts.merge(device_id: 200)
    assert merged[:device_id] == 200
    assert merged[:destination] == npci_source
  end

  test "merge omits npci destination and invoke device_id without npci source on shared addresses" do
    store(100)
    store(200)

    merged = RequestOpts.merge(remote_device_id: 200)
    assert merged[:remote_device_id] == 200
    refute Keyword.has_key?(merged, :device_id)
    refute Keyword.has_key?(merged, :destination)
  end
end
