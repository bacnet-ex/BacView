defmodule BacView.BACnet.Stack.Runtime do
  @moduledoc false
  use Supervisor

  alias BACnet.Stack.Client
  alias BACnet.Stack.Segmentator
  alias BACnet.Stack.SegmentsStore
  alias BacView.BACnet.TransportResolver
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

    with {:ok, module, opts} <- TransportResolver.resolve(settings) do
      {:ok, stack_children(module, module.stack_transport_module(), opts, settings)}
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
end
