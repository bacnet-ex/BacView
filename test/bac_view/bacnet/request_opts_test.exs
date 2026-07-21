defmodule BacView.BACnet.RequestOptsTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.NpciTarget
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.IAm
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.RequestOpts

  @table :bacview_devices
  @share_table :bacview_device_share
  @address {{10, 0, 0, 5}, 47_808}

  setup do
    for table <- [@table, @share_table] do
      if :ets.whereis(table) == :undefined do
        :ets.new(table, [:named_table, :set, :public])
      else
        :ets.delete_all_objects(table)
      end
    end

    on_exit(fn ->
      for table <- [@table, @share_table] do
        if :ets.whereis(table) != :undefined do
          :ets.delete_all_objects(table)
        end
      end
    end)

    :ok
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

  test "for_device fills remote_device_id without adding invoke id when there is no NPCI source" do
    store(100)

    merged = RequestOpts.for_device(100, [])
    assert merged[:remote_device_id] == 100
    refute Keyword.has_key?(merged, :device_id)
    refute Keyword.has_key?(merged, :destination)
    assert is_integer(merged[:max_apdu])
    assert merged[:max_apdu] == merged[:max_apdu_length]
  end

  test "merge injects apdu opts when device is unknown" do
    merged = RequestOpts.merge(device_id: 404)
    assert merged[:device_id] == 404
    assert is_integer(merged[:max_apdu])
  end

  test "for_device adds npci destination but not invoke device_id on shared addresses" do
    npci_source = %NpciTarget{net: 3, address: 200}

    store(100)
    store(200, npci_source)

    merged = RequestOpts.for_device(200, remote_device_id: 200)
    assert merged[:remote_device_id] == 200
    assert merged[:destination] == npci_source
    refute Keyword.has_key?(merged, :device_id)
  end

  test "for_device adds npci destination and invoke device_id for a routed unique address" do
    npci_source = %NpciTarget{net: 3, address: 200}

    store(200, npci_source)

    merged = RequestOpts.for_device(200, [])
    assert merged[:device_id] == 200
    assert merged[:remote_device_id] == 200
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

  describe "with shared reduction disabled" do
    setup do
      previous =
        Application.get_env(:bacview, :property_read_concurrency_disable_shared_reduction)

      Application.put_env(:bacview, :property_read_concurrency_disable_shared_reduction, true)

      on_exit(fn ->
        restore_disable_shared_reduction(previous)
      end)

      :ok
    end

    test "shared_address? is false when multiple devices share an address" do
      store(100)
      store(200)

      refute RequestOpts.shared_address?(@address)
    end

    test "for_device adds invoke device_id for routed device on shared gateway" do
      npci_source = %NpciTarget{net: 3, address: 200}

      store(100)
      store(200, npci_source)

      merged = RequestOpts.for_device(200, remote_device_id: 200)
      assert merged[:remote_device_id] == 200
      assert merged[:destination] == npci_source
      assert merged[:device_id] == 200
    end
  end

  defp restore_disable_shared_reduction(nil),
    do: Application.delete_env(:bacview, :property_read_concurrency_disable_shared_reduction)

  defp restore_disable_shared_reduction(value),
    do: Application.put_env(:bacview, :property_read_concurrency_disable_shared_reduction, value)
end
