defmodule BacView.BACnet.AddressTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.NpciTarget
  alias BacView.BACnet.Address

  require Address

  test "parse_host accepts IPv4" do
    assert {:ok, {192, 168, 1, 10}} = Address.parse_host("192.168.1.10")
  end

  test "parse_host rejects invalid input" do
    assert {:error, :invalid_host} = Address.parse_host("not-an-ip")
  end

  describe "parse_npci_station/1" do
    test "parses an optional routed station independently of the transport" do
      assert {:ok, nil} = Address.parse_npci_station(nil)
      assert {:ok, nil} = Address.parse_npci_station("  ")

      assert {:ok, %NpciTarget{net: 77, address: <<42>>}} =
               Address.parse_npci_station(" 77 / 42 ")

      assert {:ok, %NpciTarget{net: 1, address: <<0>>}} = Address.parse_npci_station("1/0")

      assert {:ok, %NpciTarget{net: 65_534, address: <<192, 168, 1, 10, 186, 193>>}} =
               Address.parse_npci_station("65534/192.168.1.10:47809")

      assert {:ok, %NpciTarget{net: 100, address: <<192, 168, 1, 10, 186, 192>>}} =
               Address.parse_npci_station("100/192.168.1.10")

      assert {:ok, %NpciTarget{net: 100, address: <<2, 0, 170, 0, 0, 66>>}} =
               Address.parse_npci_station("100/02:00:aa:00:00:42")
    end

    test "rejects invalid networks, broadcasts, and malformed station addresses" do
      for value <- [
            "42",
            "0/42",
            "65535/42",
            "1/",
            "1/broadcast",
            "1/255",
            "1/192.168.1.10:65536",
            "1/192.168.1.10/42",
            "1/0:01",
            "1/00:GG",
            "1/02:00:00:00:00:00:00:00"
          ] do
        assert {:error, :invalid_npci_source} = Address.parse_npci_station(value)
      end
    end

    test "preserves leading zero octets and round-trips all supported address lengths" do
      for {input, address} <- [
            {"1/0", <<0>>},
            {"1/42", <<42>>},
            {"1/254", <<254>>},
            {"1/00:00", <<0, 0>>},
            {"1/00:2a", <<0, 42>>},
            {"1/00:00:2A", <<0, 0, 42>>},
            {"1/00:80:FF:2A", <<0, 128, 255, 42>>},
            {"1/00:00:00:00:2A", <<0, 0, 0, 0, 42>>},
            {"1/00:00:00:00:00:2A", <<0, 0, 0, 0, 0, 42>>},
            {"1/00:00:00:00:00:00", <<0, 0, 0, 0, 0, 0>>},
            {"1/00:00:00:00:00:00:2A", <<0, 0, 0, 0, 0, 0, 42>>},
            {"1/0.1.2.3:47808", <<0, 1, 2, 3, 186, 192>>}
          ] do
        target = %NpciTarget{net: 1, address: address}
        assert {:ok, ^target} = Address.parse_npci_station(input)
        assert Address.is_npci_station(target)
        assert {:ok, ^target} = Address.parse_npci_station(Address.format_npci_target(target))
      end
    end
  end

  describe "is_npci_station/1" do
    test "accepts one to seven opaque octets on remote station networks" do
      for net <- [1, 65_534], length <- 1..7 do
        target = %NpciTarget{net: net, address: :binary.copy(<<0>>, length)}
        assert Address.is_npci_station(target)
      end
    end

    test "rejects broadcasts, invalid networks, and invalid address representations" do
      for net <- [0, 65_535, nil], address <- [<<42>>, <<0, 42>>] do
        refute Address.is_npci_station(%NpciTarget{net: net, address: address})
      end

      for address <- [nil, <<>>, <<0::64>>, 42, -1, "12345678", <<1::1>>] do
        refute Address.is_npci_station(%NpciTarget{net: 1, address: address})
      end

      refute Address.is_npci_station(nil)
      refute Address.is_npci_station(%{net: 1, address: <<42>>})
    end
  end

  describe "parse_transport_destination/2" do
    test "parses IPv4 host with default port" do
      assert {:ok, {{192, 168, 1, 10}, 47_808}} =
               Address.parse_transport_destination("192.168.1.10", "ipv4")
    end

    test "parses IPv4 host with explicit port" do
      assert {:ok, {{10, 0, 0, 1}, 47_809}} =
               Address.parse_transport_destination("10.0.0.1:47809", "ipv4")
    end

    test "rejects invalid IPv4 host and port" do
      assert {:error, :invalid_host} = Address.parse_transport_destination("", "ipv4")
      assert {:error, :invalid_host} = Address.parse_transport_destination("not-an-ip", "ipv4")
      assert {:error, :invalid_port} = Address.parse_transport_destination("10.0.0.1:", "ipv4")
      assert {:error, :invalid_port} = Address.parse_transport_destination("10.0.0.1:abc", "ipv4")
    end

    test "parses MS/TP unicast MAC 0..254" do
      assert {:ok, 0} = Address.parse_transport_destination("0", "mstp")
      assert {:ok, 42} = Address.parse_transport_destination("42", "mstp")
      assert {:ok, 254} = Address.parse_transport_destination("254", "mstp")
    end

    test "rejects invalid MS/TP addresses" do
      assert {:error, :invalid_mstp_address} = Address.parse_transport_destination("", "mstp")
      assert {:error, :invalid_mstp_address} = Address.parse_transport_destination("255", "mstp")
      assert {:error, :invalid_mstp_address} = Address.parse_transport_destination("-1", "mstp")

      assert {:error, :invalid_mstp_address} =
               Address.parse_transport_destination("192.168.1.10", "mstp")
    end

    test "parses and formats an SC VMAC and rejects reserved addresses" do
      assert {:ok, <<2, 0, 170, 0, 0, 66>> = vmac} =
               Address.parse_transport_destination(" 02:00:aa:00:00:42 ", "bacnet_sc")

      assert Address.destination_meta(vmac) == %{ip: nil, port: nil, label: "02:00:AA:00:00:42"}

      for invalid <- ["00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "02:00:AA:00:00", "10.0.0.1"] do
        assert {:error, :invalid_sc_vmac} =
                 Address.parse_transport_destination(invalid, "bacnet_sc")
      end
    end

    test "rejects unknown transports" do
      assert {:error, :unsupported_transport} =
               Address.parse_transport_destination("10.0.0.1", "unknown")
    end
  end

  test "parse_port accepts integer and string" do
    assert {:ok, 47_808} = Address.parse_port(47_808)
    assert {:ok, 47_808} = Address.parse_port("47808")
    assert Address.default_ipv4_port() == 47_808
    assert Address.valid_ipv4_port?(47_808)
    assert Address.valid_ipv4_port?(65_535)
    refute Address.valid_ipv4_port?(47_807)
    refute Address.valid_ipv4_port?(65_536)
  end

  test "format_ip renders tuple" do
    assert Address.format_ip({10, 0, 0, 1}) == "10.0.0.1"
  end

  describe "transport destination helpers" do
    test "normalize_destination keeps IPv4 and MS/TP addresses" do
      assert Address.normalize_destination({{10, 0, 0, 1}, 47_808}) == {{10, 0, 0, 1}, 47_808}

      assert Address.normalize_destination({{10, 0, 0, 1}, 47_808, :tag}) ==
               {{10, 0, 0, 1}, 47_808}

      assert Address.normalize_destination(42) == 42
    end

    test "format_destination renders IPv4 and MS/TP addresses" do
      assert Address.format_destination({{10, 0, 0, 1}, 47_808}) == "10.0.0.1:47808"
      assert Address.format_destination(42) == "42"
    end

    test "format_npci_target renders NPCI source targets" do
      assert Address.format_npci_target(nil) == "none"
      assert Address.format_npci_target(%NpciTarget{net: 2, address: nil}) == "2/broadcast"
      assert Address.format_npci_target(%NpciTarget{net: 2, address: <<42>>}) == "2/42"

      bacnet_ip_address = <<10, 130, 0, 221, 47_808::16>>

      assert Address.format_npci_target(%NpciTarget{net: 1, address: bacnet_ip_address}) ==
               "1/10.130.0.221:47808"
    end

    test "format_npci_target keeps station byte lengths distinct" do
      assert Address.format_npci_target(%NpciTarget{net: 2, address: <<0>>}) == "2/0"
      assert Address.format_npci_target(%NpciTarget{net: 2, address: <<0, 42>>}) == "2/00:2A"

      assert Address.format_npci_target(%NpciTarget{net: 2, address: <<0, 128, 255>>}) ==
               "2/00:80:FF"

      assert Address.format_npci_target(%NpciTarget{net: 2, address: <<0, 0, 0, 0, 0, 0>>}) ==
               "2/00:00:00:00:00:00"
    end

    test "destination_meta derives display fields" do
      assert Address.destination_meta({{10, 0, 0, 1}, 47_808}) == %{
               ip: "10.0.0.1",
               port: 47_808,
               label: "10.0.0.1:47808"
             }

      assert Address.destination_meta(42) == %{ip: nil, port: nil, label: "42"}
    end

    test "same_destination? compares normalized addresses" do
      assert Address.same_destination?({{10, 0, 0, 1}, 47_808, :tag}, {{10, 0, 0, 1}, 47_808})
      refute Address.same_destination?({{10, 0, 0, 1}, 47_808}, {{10, 0, 0, 2}, 47_808})
      assert Address.same_destination?(42, 42)
      refute Address.same_destination?(42, 43)
    end

    test "format_device_address prefers address_label and falls back to legacy fields" do
      assert Address.format_device_address(%{address_label: "MS/TP 42", address: 42}) ==
               "MS/TP 42"

      assert Address.format_device_address(%{
               ip: "10.0.0.1",
               port: 47_808,
               address: {{10, 0, 0, 1}, 47_808}
             }) == "10.0.0.1:47808"

      assert Address.format_device_address(%{address: 42}) == "42"
    end
  end

  describe "expand_scan_targets/1" do
    test "expands a single octet range" do
      assert {:ok, ips} = Address.expand_scan_targets("192.168.100.[31-35]")

      assert ips == [
               {192, 168, 100, 31},
               {192, 168, 100, 32},
               {192, 168, 100, 33},
               {192, 168, 100, 34},
               {192, 168, 100, 35}
             ]
    end

    test "accepts plain IPv4 without brackets" do
      assert {:ok, [{10, 0, 0, 42}]} = Address.expand_scan_targets("10.0.0.42")
    end

    test "expands multiple octet ranges" do
      assert {:ok, ips} = Address.expand_scan_targets("192.168.[100-101].[31-32]")

      assert ips == [
               {192, 168, 100, 31},
               {192, 168, 100, 32},
               {192, 168, 101, 31},
               {192, 168, 101, 32}
             ]
    end

    test "rejects invalid range syntax" do
      assert {:error, :invalid_host} = Address.expand_scan_targets("192.168.100.[35-31]")
      assert {:error, :invalid_host} = Address.expand_scan_targets("192.168.100.[abc]")
    end
  end

  describe "expand_scan_destinations/2" do
    test "uses the default port when none is given" do
      assert {:ok, [{{192, 168, 1, 101}, 47_808}]} =
               Address.expand_scan_destinations("192.168.1.101", 47_808)

      assert {:ok, destinations} =
               Address.expand_scan_destinations("192.168.100.[31-32]", 47_809)

      assert destinations == [
               {{192, 168, 100, 31}, 47_809},
               {{192, 168, 100, 32}, 47_809}
             ]
    end

    test "accepts an explicit ip:port" do
      assert {:ok, [{{192, 168, 1, 101}, 47_808}]} =
               Address.expand_scan_destinations("192.168.1.101:47808", 47_809)

      assert {:ok, [{{192, 168, 100, 42}, 47_809}]} =
               Address.expand_scan_destinations("  192.168.100.42:47809  ", 47_808)
    end

    test "applies an explicit port to every address in a range" do
      assert {:ok, destinations} =
               Address.expand_scan_destinations("192.168.100.[31-32]:47809", 47_808)

      assert destinations == [
               {{192, 168, 100, 31}, 47_809},
               {{192, 168, 100, 32}, 47_809}
             ]
    end

    test "rejects an invalid port without using the default" do
      assert {:error, :invalid_port} =
               Address.expand_scan_destinations("192.168.1.101:", 47_808)

      assert {:error, :invalid_port} =
               Address.expand_scan_destinations("192.168.1.101:abc", 47_808)

      assert {:error, :invalid_port} =
               Address.expand_scan_destinations("192.168.1.101:65536", 47_808)

      assert {:error, :invalid_host} =
               Address.expand_scan_destinations("not-an-ip:47808", 47_808)
    end
  end
end
