defmodule BacView.BACnet.InterfaceSelection do
  @moduledoc false

  alias BacView.BACnet.NetworkInterfaces
  alias BacView.BACnet.SerialPorts

  @type option :: map()
  @type ok :: %{interface: String.t(), options: [option()]}
  @type error_meta :: %{options: [option()], interface: nil}

  @spec resolve_ipv4(String.t() | nil) :: {:ok, ok()}
  def resolve_ipv4(saved_interface) do
    {:ok, select_interface(saved_interface, ipv4_options())}
  end

  @spec resolve(String.t(), String.t() | nil) ::
          {:ok, ok()} | {:error, atom(), error_meta()}
  def resolve("ipv4", saved_interface), do: resolve_ipv4(saved_interface)

  def resolve(transport, saved_interface) do
    options = options_for(transport)

    case options do
      [] ->
        {:error, empty_error(transport), %{options: [], interface: nil}}

      _saved_interface ->
        {:ok, select_interface(saved_interface, options)}
    end
  end

  @spec options_for(String.t()) :: [option()]
  def options_for("mstp"), do: SerialPorts.list()
  def options_for(_options_for), do: NetworkInterfaces.list()

  defp ipv4_options() do
    case NetworkInterfaces.list() do
      [] -> [loopback_option()]
      options -> options
    end
  end

  defp select_interface(saved_interface, options) do
    interface =
      if saved_interface in Enum.map(options, & &1.value) do
        saved_interface
      else
        hd(options).value
      end

    %{interface: interface, options: options}
  end

  defp loopback_option() do
    %{
      value: "lo",
      label: "lo — 127.0.0.1",
      name: "lo",
      address: {127, 0, 0, 1}
    }
  end

  defp empty_error("mstp"), do: :no_serial_ports
  defp empty_error(_empty_error), do: :no_network_interfaces
end
