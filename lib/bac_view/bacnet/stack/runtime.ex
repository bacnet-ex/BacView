defmodule BacView.BACnet.Stack.Runtime do
  @moduledoc false
  use Supervisor

  alias BACnet.Stack.Client
  alias BACnet.Stack.Segmentator
  alias BACnet.Stack.SegmentsStore
  alias BACnet.Stack.Transport.IPv4Transport
  alias BacView.BACnet.InterfaceSelection
  alias BacView.BACnet.Transport.IPv4
  alias BacView.BACnet.Transport.MSTP
  alias BacView.Settings

  @segmentator BacView.BACnet.Segmentator
  @segments_store BacView.BACnet.SegmentsStore
  @client BacView.BACnet.ClientStack
  @transport BacView.BACnet.TransportLayer

  @spec child_spec() :: Supervisor.child_spec()
  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :temporary,
      type: :supervisor
    }
  end

  @spec start_link() :: Supervisor.on_start()
  def start_link() do
    with {:ok, children} <- build_children() do
      Supervisor.start_link(__MODULE__, children, name: __MODULE__)
    end
  end

  @impl true
  def init(children) when is_list(children) do
    Supervisor.init(children, strategy: :one_for_all)
  end

  @spec build_children() :: {:ok, list()} | {:error, term()}
  def build_children() do
    settings = Settings.get()

    case settings.transport do
      "mstp" -> build_transport_children(settings, MSTP, "mstp")
      _build_children -> build_ipv4_children(settings)
    end
  end

  defp build_ipv4_children(settings) do
    {:ok, %{interface: interface}} = InterfaceSelection.resolve_ipv4(settings.interface)
    transport_opts = ipv4_transport_opts(interface, settings.ipv4_port)
    {:ok, stack_children(IPv4, IPv4Transport, transport_opts)}
  end

  defp build_transport_children(settings, transport_module, transport_name) do
    case InterfaceSelection.resolve(transport_name, settings.interface) do
      {:ok, %{interface: interface}} ->
        transport_opts = transport_opts(settings, interface, transport_name)

        if transport_module.available?() do
          {:ok,
           stack_children(
             transport_module,
             transport_module.stack_transport_module(),
             transport_opts
           )}
        else
          {:error, {:transport_not_available, transport_name}}
        end

      {:error, reason, _settings} ->
        {:error, reason}
    end
  end

  defp stack_children(transport_module, stack_transport, transport_opts) do
    [
      {transport_module, [client: @client, transport_opts: transport_opts]},
      {Segmentator, [name: @segmentator]},
      {SegmentsStore, [name: @segments_store]},
      {Client,
       [
         name: @client,
         segmentator: @segmentator,
         segments_store: @segments_store,
         transport: {stack_transport, @transport}
       ]}
    ]
  end

  defp transport_opts(settings, interface, "mstp") do
    [
      name: @transport,
      port_name: interface,
      local_address: settings.mstp_local_address,
      baudrate: settings.mstp_baud_rate
    ]
  end

  defp transport_opts(settings, interface, "ipv4") do
    ipv4_transport_opts(interface, settings.ipv4_port)
  end

  defp transport_opts(_settings, interface, _transport) do
    [name: @transport, local_ip: interface]
  end

  defp ipv4_transport_opts(interface, port) do
    [name: @transport, local_ip: interface, bacnet_port: port]
  end
end
