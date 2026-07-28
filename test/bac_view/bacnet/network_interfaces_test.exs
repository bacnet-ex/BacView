defmodule BacView.BACnet.NetworkInterfacesTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.NetworkInterfaces

  describe "resolve_display_name/4" do
    @friendly %{"192.168.1.50" => "Ethernet 8"}

    test "returns friendly name when present" do
      assert NetworkInterfaces.resolve_display_name(
               @friendly,
               "192.168.1.50",
               "\\DEVICE\\TCPIP_{GUID}",
               true
             ) == "Ethernet 8"

      assert NetworkInterfaces.resolve_display_name(
               @friendly,
               "192.168.1.50",
               "eth0",
               false
             ) == "Ethernet 8"
    end

    test "returns nil when friendly name is required and missing" do
      assert NetworkInterfaces.resolve_display_name(
               @friendly,
               "10.0.0.1",
               "\\DEVICE\\TCPIP_{OTHER}",
               true
             ) == nil
    end

    test "falls back to hardware name when friendly name is not required" do
      assert NetworkInterfaces.resolve_display_name(
               @friendly,
               "10.0.0.1",
               "eth0",
               false
             ) == "eth0"
    end
  end

  test "format_ip/1 formats IPv4 tuples" do
    assert NetworkInterfaces.format_ip({192, 168, 1, 50}) == "192.168.1.50"
  end

  test "list/0 returns option maps with value, label, name, and address" do
    options = NetworkInterfaces.list()

    assert is_list(options)

    for option <- options do
      assert is_binary(option.value)
      assert is_binary(option.label)
      assert is_binary(option.name)
      assert match?({_, _, _, _}, option.address)
      assert String.contains?(option.label, NetworkInterfaces.format_ip(option.address))
    end
  end
end
