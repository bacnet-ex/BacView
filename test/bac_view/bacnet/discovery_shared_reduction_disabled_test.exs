defmodule BacView.BACnet.DiscoverySharedReductionDisabledTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.IAmCollector

  @iam_apdu %UnconfirmedServiceRequest{
    service: :i_am,
    parameters: [
      object_identifier: %ObjectIdentifier{type: :device, instance: 42},
      unsigned_integer: 1476,
      enumerated: 3,
      unsigned_integer: 999
    ]
  }

  setup do
    previous =
      Application.get_env(:bacview, :property_read_concurrency_disable_shared_reduction)

    Application.put_env(:bacview, :property_read_concurrency_disable_shared_reduction, true)
    # DashboardLive scan form tests leave filters in Application env; clear them so
    # I-Am upserts are not rejected mid-suite.
    Discovery.set_acceptance_filters(low_limit: nil, high_limit: nil, vendor_id: nil)

    for table <- [:bacview_devices, :bacview_device_share] do
      if :ets.whereis(table) == :undefined do
        :ets.new(table, [:named_table, :set, :public])
      else
        :ets.delete_all_objects(table)
      end
    end

    on_exit(fn ->
      restore_disable_shared_reduction(previous)
      Discovery.set_acceptance_filters(low_limit: nil, high_limit: nil, vendor_id: nil)

      for table <- [:bacview_devices, :bacview_device_share] do
        if :ets.whereis(table) != :undefined do
          :ets.delete_all_objects(table)
        end
      end
    end)

    {:ok, iam: elem(IAmCollector.parse_iam(@iam_apdu), 1)}
  end

  test "does not reduce concurrency or track shared destination for a shared gateway", %{
    iam: iam
  } do
    gateway = {{10, 0, 0, 1}, 47_808}
    iam_100 = %{iam | device: %{iam.device | instance: 100}}
    iam_200 = %{iam | device: %{iam.device | instance: 200}}

    Discovery.upsert_iam_device(iam_100, gateway)
    Discovery.upsert_iam_device(iam_200, gateway)

    assert {:ok, device_100} = Discovery.get_device(100)
    assert {:ok, device_200} = Discovery.get_device(200)
    refute Map.has_key?(device_100, :max_concurrency)
    refute Map.has_key?(device_200, :max_concurrency)
    refute Map.get(device_100, :shared_destination?)
    refute Map.get(device_200, :shared_destination?)
    refute Discovery.shared_destination?(gateway)
    assert :ets.tab2list(:bacview_device_share) == []
  end

  test "does not reduce concurrency when only I-Am UDP source is shared (BBMD)", %{iam: iam} do
    bbmd_source = {{192, 168, 100, 31}, 47_808}
    iam_100 = %{iam | device: %{iam.device | instance: 100}}
    iam_200 = %{iam | device: %{iam.device | instance: 200}}

    Discovery.upsert_iam_device(iam_100, {{192, 168, 100, 111}, 47_808}, nil, bbmd_source)
    Discovery.upsert_iam_device(iam_200, {{192, 168, 100, 112}, 47_808}, nil, bbmd_source)

    assert {:ok, device_100} = Discovery.get_device(100)
    assert {:ok, device_200} = Discovery.get_device(200)
    refute Map.has_key?(device_100, :max_concurrency)
    refute Map.has_key?(device_200, :max_concurrency)
    refute Map.get(device_100, :shared_destination?)
    refute Map.get(device_200, :shared_destination?)
  end

  defp restore_disable_shared_reduction(nil),
    do: Application.delete_env(:bacview, :property_read_concurrency_disable_shared_reduction)

  defp restore_disable_shared_reduction(value),
    do: Application.put_env(:bacview, :property_read_concurrency_disable_shared_reduction, value)
end
