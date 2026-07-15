defmodule BacView.BACnet.DiscoveryTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.IAmCollector
  alias BacView.Settings

  @iam_apdu %UnconfirmedServiceRequest{
    service: :i_am,
    parameters: [
      object_identifier: %ObjectIdentifier{type: :device, instance: 42},
      unsigned_integer: 1476,
      enumerated: 3,
      unsigned_integer: 999
    ]
  }

  test "normalize_device_name sanitizes BACnet object names" do
    assert Discovery.normalize_device_name("AHU-1") == "AHU-1"
    assert Discovery.normalize_device_name("") == nil
    assert Discovery.normalize_device_name(nil) == nil
  end

  test "normalize_device_description converts Latin-1 bytes to UTF-8" do
    latin1 = <<"K\xE4ltemaschine 1 / RHOSS FP ECO-E VFD TCAITE 1325 RH00376802">>

    assert Discovery.normalize_device_description(latin1) ==
             "Kältemaschine 1 / RHOSS FP ECO-E VFD TCAITE 1325 RH00376802"

    assert String.valid?(Discovery.normalize_device_description(latin1))
  end

  describe "cancel_scan/0" do
    setup do
      if :ets.whereis(:bacview_devices) == :undefined do
        :ets.new(:bacview_devices, [:named_table, :set, :public])
      end

      on_exit(fn ->
        if :ets.whereis(:bacview_devices) != :undefined do
          :ets.delete(:bacview_devices)
        end
      end)

      :ok
    end

    test "removes all discovered devices" do
      :ets.insert(:bacview_devices, {42, %{id: 42, instance: 42}})

      assert Discovery.cancel_scan() == :ok
      assert Discovery.list_devices() == []
    end
  end

  describe "clear_devices/0" do
    setup do
      if :ets.whereis(:bacview_devices) == :undefined do
        :ets.new(:bacview_devices, [:named_table, :set, :public])
      end

      on_exit(fn ->
        if :ets.whereis(:bacview_devices) != :undefined do
          :ets.delete(:bacview_devices)
        end
      end)

      :ok
    end

    test "removes all discovered devices" do
      :ets.insert(:bacview_devices, {42, %{id: 42, instance: 42}})

      assert Discovery.clear_devices() == :ok
      assert Discovery.list_devices() == []
    end
  end

  describe "shared destination max_concurrency" do
    setup do
      for table <- [:bacview_devices, :bacview_device_share] do
        if :ets.whereis(table) == :undefined do
          :ets.new(table, [:named_table, :set, :public])
        else
          :ets.delete_all_objects(table)
        end
      end

      on_exit(fn ->
        for table <- [:bacview_devices, :bacview_device_share] do
          if :ets.whereis(table) != :undefined do
            :ets.delete_all_objects(table)
          end
        end
      end)

      {:ok, iam: elem(IAmCollector.parse_iam(@iam_apdu), 1)}
    end

    test "does not set max_concurrency when only I-Am UDP source is shared (BBMD)", %{iam: iam} do
      # Who-Is via BBMD: every I-Am arrives from the BBMD IP, but each device has
      # its own BACnet/IP address for subsequent requests.
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
    end

    test "sets max_concurrency to 1 when multiple devices share a request destination", %{
      iam: iam
    } do
      gateway = {{10, 0, 0, 1}, 47_808}
      iam_100 = %{iam | device: %{iam.device | instance: 100}}
      iam_200 = %{iam | device: %{iam.device | instance: 200}}

      Discovery.upsert_iam_device(iam_100, gateway)
      Discovery.upsert_iam_device(iam_200, gateway)

      assert {:ok, %{max_concurrency: 1, shared_destination?: true}} = Discovery.get_device(100)
      assert {:ok, %{max_concurrency: 1, shared_destination?: true}} = Discovery.get_device(200)
      assert Discovery.shared_destination?(gateway)
    end

    test "clears max_concurrency when only one device remains on a destination", %{iam: iam} do
      gateway = {{10, 0, 0, 1}, 47_808}
      iam_100 = %{iam | device: %{iam.device | instance: 100}}
      iam_200 = %{iam | device: %{iam.device | instance: 200}}

      Discovery.upsert_iam_device(iam_100, gateway)
      Discovery.upsert_iam_device(iam_200, gateway)

      :ets.delete_all_objects(:bacview_devices)
      Discovery.upsert_iam_device(iam_100, gateway)

      assert {:ok, device} = Discovery.get_device(100)
      refute Map.has_key?(device, :max_concurrency)
      refute Map.get(device, :shared_destination?)
    end

    test "does not set max_concurrency for distinct destinations", %{iam: iam} do
      iam_100 = %{iam | device: %{iam.device | instance: 100}}
      iam_200 = %{iam | device: %{iam.device | instance: 200}}

      Discovery.upsert_iam_device(iam_100, {{10, 0, 0, 5}, 47_808})
      Discovery.upsert_iam_device(iam_200, {{10, 0, 0, 6}, 47_808})

      assert {:ok, device_100} = Discovery.get_device(100)
      assert {:ok, device_200} = Discovery.get_device(200)
      refute Map.has_key?(device_100, :max_concurrency)
      refute Map.has_key?(device_200, :max_concurrency)
    end
  end

  describe "upsert_iam_device/2" do
    setup do
      if :ets.whereis(:bacview_devices) == :undefined do
        :ets.new(:bacview_devices, [:named_table, :set, :public])
      end

      on_exit(fn ->
        if :ets.whereis(:bacview_devices) != :undefined do
          :ets.delete(:bacview_devices)
        end
      end)

      {:ok, iam: elem(IAmCollector.parse_iam(@iam_apdu), 1), address: {{10, 0, 0, 42}, 47_808}}
    end

    test "creates a discovered device on first I-Am", %{iam: iam, address: address} do
      assert %{
               status: :discovered,
               id: 42,
               name: nil,
               loaded_at: nil,
               address_label: "10.0.0.42:47808"
             } =
               Discovery.upsert_iam_device(iam, address)

      assert {:ok, %{status: :discovered}} = Discovery.get_device(42)
    end

    test "stores MS/TP MAC addresses as integer destinations", %{iam: iam} do
      assert %{status: :discovered, address: 42, ip: nil, port: nil, address_label: "42"} =
               Discovery.upsert_iam_device(iam, 42)

      assert {:ok, %{address: 42, address_label: "42"}} = Discovery.get_device(42)
    end

    test "keeps loaded status when the same MS/TP device sends another I-Am", %{iam: iam} do
      loaded_at = ~U[2026-01-15 12:00:00Z]
      mstp_address = 42

      :ets.insert(:bacview_devices, {
        42,
        %{
          id: 42,
          instance: 42,
          address: mstp_address,
          ip: nil,
          port: nil,
          address_label: "42",
          status: :loaded,
          name: "AHU-1",
          object_count: 12,
          loaded_at: loaded_at,
          discovered_at: loaded_at
        }
      })

      assert %{status: :loaded, address: 42, name: "AHU-1"} =
               Discovery.upsert_iam_device(iam, mstp_address)
    end

    test "keeps loaded status when the same device sends another I-Am", %{
      iam: iam,
      address: address
    } do
      loaded_at = ~U[2026-01-15 12:00:00Z]

      :ets.insert(:bacview_devices, {
        42,
        %{
          id: 42,
          instance: 42,
          address: address,
          ip: "10.0.0.42",
          port: 47_808,
          status: :loaded,
          name: "AHU-1",
          object_count: 12,
          loaded_at: loaded_at,
          discovered_at: loaded_at
        }
      })

      assert %{status: :loaded, name: "AHU-1", object_count: 12, loaded_at: ^loaded_at} =
               Discovery.upsert_iam_device(iam, address)

      assert {:ok, %{status: :loaded, name: "AHU-1", object_count: 12, loaded_at: ^loaded_at}} =
               Discovery.get_device(42)
    end

    test "resets to discovered when the source address changes", %{iam: iam, address: address} do
      loaded_at = ~U[2026-01-15 12:00:00Z]

      :ets.insert(:bacview_devices, {
        42,
        %{
          id: 42,
          instance: 42,
          address: address,
          ip: "10.0.0.42",
          port: 47_808,
          status: :loaded,
          name: "AHU-1",
          object_count: 12,
          loaded_at: loaded_at,
          discovered_at: loaded_at
        }
      })

      new_address = {{10, 0, 0, 99}, 47_808}

      assert %{status: :discovered, name: nil, object_count: nil, loaded_at: nil} =
               Discovery.upsert_iam_device(iam, new_address)

      assert {:ok, %{status: :discovered, address: ^new_address}} = Discovery.get_device(42)
    end
  end

  describe "parse_scan_params/1" do
    test "defaults timeout when omitted" do
      assert Discovery.parse_scan_params(%{}) == {:ok, [timeout: Discovery.default_timeout()]}
    end

    test "accepts custom timeout" do
      assert Discovery.parse_scan_params(%{"timeout_ms" => "2500"}) == {:ok, [timeout: 2500]}
    end

    test "rejects timeout below minimum on server" do
      assert Discovery.parse_scan_params(%{"timeout_ms" => "499"}) ==
               {:error, {:timeout_too_low, Discovery.min_timeout()}}
    end

    test "rejects invalid timeout" do
      assert Discovery.parse_scan_params(%{"timeout_ms" => "abc"}) == {:error, :invalid_timeout}
    end

    test "parses optional target IP for unicast Who-Is" do
      assert {:ok, opts} =
               Discovery.parse_scan_params(%{"timeout_ms" => "1000", "target_ip" => "10.0.0.42"})

      assert Keyword.fetch!(opts, :timeout) == 1000
      assert Keyword.fetch!(opts, :destination) == [{{10, 0, 0, 42}, Settings.get().ipv4_port}]
    end

    test "parses target IP octet range for multiple unicast Who-Is" do
      assert {:ok, opts} =
               Discovery.parse_scan_params(%{
                 "timeout_ms" => "1000",
                 "target_ip" => "192.168.100.[31-35]"
               })

      assert Keyword.fetch!(opts, :timeout) == 1000

      port = Settings.get().ipv4_port

      assert Keyword.fetch!(opts, :destination) == [
               {{192, 168, 100, 31}, port},
               {{192, 168, 100, 32}, port},
               {{192, 168, 100, 33}, port},
               {{192, 168, 100, 34}, port},
               {{192, 168, 100, 35}, port}
             ]
    end

    test "rejects oversized target IP ranges" do
      assert Discovery.parse_scan_params(%{"target_ip" => "10.0.0.[0-300]"}) ==
               {:error, :invalid_host}

      assert Discovery.parse_scan_params(%{"target_ip" => "10.0.[0-255].[0-255]"}) ==
               {:error, {:too_many_targets, 256}}
    end

    test "ignores blank target IP" do
      assert Discovery.parse_scan_params(%{"timeout_ms" => "1000", "target_ip" => "  "}) ==
               {:ok, [timeout: 1000]}
    end

    test "rejects invalid target IP" do
      assert Discovery.parse_scan_params(%{"target_ip" => "not-an-ip"}) == {:error, :invalid_host}
    end

    test "parses optional device ID range for Who-Is" do
      assert {:ok, opts} =
               Discovery.parse_scan_params(%{
                 "timeout_ms" => "1000",
                 "device_id_low" => "100",
                 "device_id_high" => "200"
               })

      assert Keyword.fetch!(opts, :timeout) == 1000
      assert Keyword.fetch!(opts, :low_limit) == 100
      assert Keyword.fetch!(opts, :high_limit) == 200
      refute Keyword.has_key?(opts, :vendor_id)
    end

    test "ignores blank device ID range fields" do
      assert {:ok, opts} =
               Discovery.parse_scan_params(%{
                 "device_id_low" => " ",
                 "device_id_high" => ""
               })

      refute Keyword.has_key?(opts, :low_limit)
      refute Keyword.has_key?(opts, :high_limit)
    end

    test "rejects invalid device ID values" do
      assert Discovery.parse_scan_params(%{"device_id_low" => "abc"}) ==
               {:error, :invalid_device_id}

      assert Discovery.parse_scan_params(%{"device_id_high" => "5000000"}) ==
               {:error, :invalid_device_id}
    end

    test "rejects device ID range when low exceeds high" do
      assert Discovery.parse_scan_params(%{"device_id_low" => "500", "device_id_high" => "100"}) ==
               {:error, :invalid_device_range}
    end

    test "parses optional vendor ID filter" do
      assert {:ok, opts} =
               Discovery.parse_scan_params(%{"vendor_id" => "5"})

      assert Keyword.fetch!(opts, :vendor_id) == 5
    end

    test "ignores blank vendor ID" do
      assert {:ok, opts} = Discovery.parse_scan_params(%{"vendor_id" => "  "})
      refute Keyword.has_key?(opts, :vendor_id)
    end

    test "rejects invalid vendor ID" do
      assert Discovery.parse_scan_params(%{"vendor_id" => "70000"}) ==
               {:error, :invalid_vendor_id}
    end
  end
end
