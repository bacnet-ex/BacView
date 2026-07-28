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

  @doc false
  @spec resolve_display_name(%{String.t() => String.t()}, String.t(), String.t(), boolean()) ::
          String.t() | nil
  def resolve_display_name(friendly_names, ip_str, hardware_name, require_friendly_name?)

  def resolve_display_name(friendly_names, ip_str, _hardware_name, true) do
    Map.get(friendly_names, ip_str)
  end

  def resolve_display_name(friendly_names, ip_str, hardware_name, false) do
    Map.get(friendly_names, ip_str, hardware_name)
  end

  defp interface_options({name, addrs}, friendly_names) do
    name = to_string(name)

    Enum.flat_map(addrs, fn {addr, _subnet, _broadcast} ->
      case interface_option(name, addr, friendly_names) do
        nil -> []
        option -> [option]
      end
    end)
  end

  defp interface_option(name, ip4, friendly_names) do
    ip_str = format_ip(ip4)

    case resolve_display_name(
           friendly_names,
           ip_str,
           name,
           require_friendly_name?()
         ) do
      nil ->
        nil

      display_name ->
        %{
          value: name,
          label: "#{display_name} - #{ip_str}",
          name: name,
          address: ip4
        }
    end
  end

  if match?({:win32, _}, :os.type()) do
    alias BacView.BACnet.WinNetworkAddress

    defp friendly_names_by_ip() do
      WinNetworkAddress.friendly_names_by_ip()
    end

    # On Windows, interfaces without a netsh friendly name are not usable for
    # BACnet binding (raw hardware names are left over from virtual/unbound NICs).
    defp require_friendly_name?(), do: true
  else
    defp friendly_names_by_ip(), do: %{}
    defp require_friendly_name?(), do: false
  end
end
