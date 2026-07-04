defmodule BacView.BACnet.AddressTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Address

  test "parse_host accepts IPv4" do
    assert {:ok, {192, 168, 1, 10}} = Address.parse_host("192.168.1.10")
  end

  test "parse_host rejects invalid input" do
    assert {:error, :invalid_host} = Address.parse_host("not-an-ip")
  end

  test "parse_port accepts integer and string" do
    assert {:ok, 47_808} = Address.parse_port(47_808)
    assert {:ok, 47_808} = Address.parse_port("47808")
  end

  test "format_ip renders tuple" do
    assert Address.format_ip({10, 0, 0, 1}) == "10.0.0.1"
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
end
