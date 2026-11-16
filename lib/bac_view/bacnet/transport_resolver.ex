defmodule BacView.BACnet.TransportResolver do
  @moduledoc """
  Resolves the configured BACnet transport module and options for `BacView.BACnet.Stack`.
  """

  alias BacView.BACnet.InterfaceSelection
  alias BacView.Settings

  @transports %{
    "ipv4" => BacView.BACnet.Transport.IPv4,
    "mstp" => BacView.BACnet.Transport.MSTP,
    "bacnet_sc" => BacView.BACnet.Transport.BACnetSC
  }

  @spec resolve(Settings.t()) :: {:ok, module(), keyword()} | {:error, term()}
  def resolve(settings \\ Settings.get()) do
    with {:ok, module} <- fetch_module(settings.transport),
         :ok <- ensure_available(module, settings.transport),
         {:ok, opts} <- transport_opts(settings) do
      {:ok, module, opts}
    end
  end

  @spec supported_transports() :: [String.t()]
  def supported_transports(), do: Settings.supported_transports()

  defp ensure_available(module, name) do
    if module.available?(), do: :ok, else: {:error, {:transport_not_available, name}}
  end

  defp fetch_module(name) when is_binary(name) do
    case Map.fetch(@transports, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_transport, name}}
    end
  end

  defp transport_opts(%{transport: "bacnet_sc"} = settings) do
    with :ok <- Settings.validate_sc_config(settings) do
      {:ok,
       [
         name: BacView.BACnet.TransportLayer,
         primary_hub_uri: settings.sc_primary_hub_uri,
         failover_hub_uri: settings.sc_failover_hub_uri,
         verify_hostname: settings.sc_verify_hostname,
         ip_family: if(settings.sc_ip_family == "inet6", do: :inet6, else: :inet)
       ]}
    end
  end

  defp transport_opts(settings) do
    case InterfaceSelection.resolve(settings.transport, settings.interface) do
      {:ok, %{interface: interface}} ->
        {:ok, [name: BacView.BACnet.TransportLayer] ++ interface_opts(settings, interface)}

      {:error, reason, _selection} ->
        {:error, reason}
    end
  end

  defp interface_opts(%{transport: "mstp"} = settings, interface) do
    [
      port_name: interface,
      local_address: settings.mstp_local_address,
      baudrate: settings.mstp_baud_rate
    ]
  end

  defp interface_opts(%{transport: "ipv4"} = settings, interface),
    do: [local_ip: interface, bacnet_port: settings.ipv4_port]
end
