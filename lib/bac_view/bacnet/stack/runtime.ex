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
    {:ok, stack_children(IPv4, IPv4Transport, transport_opts, settings)}
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
             transport_opts,
             settings
           )}
        else
          {:error, {:transport_not_available, transport_name}}
        end

      {:error, reason, _settings} ->
        {:error, reason}
    end
  end

  @doc false
  @spec apply_apdu_settings(Settings.t()) :: :ok
  def apply_apdu_settings(settings) do
    configure_if_alive(@client, Client, client_opts(settings))
    configure_if_alive(@segmentator, Segmentator, segmentator_opts(settings))
    configure_if_alive(@segments_store, SegmentsStore, segments_store_opts(settings))
    :ok
  end

  @doc false
  @spec client_opts(Settings.t()) :: keyword()
  def client_opts(settings) do
    [apdu_timeout: settings.apdu_timeout, apdu_retries: settings.apdu_retries]
  end

  @doc false
  @spec segmentator_opts(Settings.t()) :: keyword()
  def segmentator_opts(settings) do
    [apdu_timeout: settings.apdu_segments_timeout, apdu_retries: settings.apdu_retries]
  end

  # SegmentsStore apdu_retries is a bacstack test-only option and must stay at the
  # default (4) for BACnet compliance.
  @doc false
  @spec segments_store_opts(Settings.t()) :: keyword()
  def segments_store_opts(settings) do
    [apdu_timeout: settings.apdu_segments_timeout, max_segments: settings.max_segments]
  end

  defp stack_children(transport_module, stack_transport, transport_opts, settings) do
    [
      {transport_module, [client: @client, transport_opts: transport_opts]},
      {Segmentator,
       [
         name: @segmentator,
         apdu_retries: settings.apdu_retries,
         apdu_timeout: settings.apdu_segments_timeout
       ]},
      {SegmentsStore,
       [
         name: @segments_store,
         apdu_timeout: settings.apdu_segments_timeout,
         max_segments: settings.max_segments
       ]},
      {Client,
       [
         name: @client,
         segmentator: @segmentator,
         segments_store: @segments_store,
         transport: {stack_transport, @transport},
         apdu_retries: settings.apdu_retries,
         apdu_timeout: settings.apdu_timeout
       ]}
    ]
  end

  defp configure_if_alive(name, module, opts) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        try do
          module.configure(name, opts)
        catch
          :exit, _reason -> :ok
        end

      nil ->
        :ok
    end
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
