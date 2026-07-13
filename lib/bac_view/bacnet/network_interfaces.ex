defmodule BacView.BACnet.NetworkInterfaces do
  @moduledoc false

  alias BACnet.Stack.Transport.IPv4Transport

  @type option :: %{
          value: String.t(),
          label: String.t(),
          name: String.t(),
          address: :inet.ip4_address()
        }

  @spec list() :: [option()]
  def list() do
    case IPv4Transport.getifaddrs() do
      {:ok, ifaddrs} ->
        friendly_names = friendly_names_by_ip()

        ifaddrs
        |> Enum.flat_map(&interface_options(&1, friendly_names))
        |> Enum.uniq_by(& &1.value)
        |> Enum.sort_by(& &1.label, :asc)

      {:error, _reason} ->
        []
    end
  end

  @spec format_ip(:inet.ip4_address()) :: String.t()
  def format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp interface_options({name, addrs}, friendly_names) do
    name = to_string(name)

    Enum.map(addrs, fn {addr, _subnet, _broadcast} ->
      interface_option(name, addr, friendly_names)
    end)
  end

  defp interface_option(name, ip4, friendly_names) do
    ip_str = format_ip(ip4)
    display_name = get_friendly_name(friendly_names, ip_str, name)

    %{
      value: name,
      label: "#{display_name} — #{ip_str}",
      name: name,
      address: ip4
    }
  end

  if match?({:win32, _}, :os.type()) do
    alias BacView.BACnet.WinNetworkAddress

    defp friendly_names_by_ip() do
      WinNetworkAddress.friendly_names_by_ip()
    end

    defp get_friendly_name(friendly_names, ip_str, name) do
      Map.get(friendly_names, ip_str, name)
    end
  else
    defp friendly_names_by_ip(), do: %{}
    defp get_friendly_name(_friendly_names, _ip_str, name), do: name
  end
end
