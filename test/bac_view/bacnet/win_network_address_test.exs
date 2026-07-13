defmodule BacView.BACnet.WinNetworkAddressTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.WinNetworkAddress

  @sample_netsh_output """
  Configuration for interface "Ethernet 8"
      DHCP enabled:                         Yes
      IP Address:                           192.168.1.50
      Subnet Prefix:                        192.168.1.0/24 (mask 255.255.255.0)
      Default Gateway:                      192.168.1.1
      Gateway Metric:                       0
      InterfaceMetric:                      55

  Konfiguration der Schnittstelle "Wi-Fi"
      DHCP aktiviert:                       Nein
      IP-Adresse:                           172.24.96.1
      Subnetzpräfix:                        172.24.96.0/20 (Maske 255.255.240.0)
      Schnittstellenmetrik:                      5000
  """

  test "parse_netsh_output maps IP addresses to friendly interface names" do
    assert WinNetworkAddress.parse_netsh_output(@sample_netsh_output) == %{
             "192.168.1.50" => "Ethernet 8",
             "172.24.96.1" => "Wi-Fi"
           }
  end

  test "parse_netsh_output returns empty map for blank output" do
    assert WinNetworkAddress.parse_netsh_output("") == %{}
  end
end
