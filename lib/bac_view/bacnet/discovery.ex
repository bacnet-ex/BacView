defmodule BacView.BACnet.Discovery do
  @moduledoc """
  BACnet network discovery via Who-Is / I-Am.
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.IAm
  alias BACnet.Protocol.Services.WhoIs
  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Address
  alias BacView.BACnet.Client
  alias BacView.BACnet.ForeignRegistration
  alias BacView.BACnet.IAmCollector
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.Settings
  alias BacView.Text

  @table :bacview_devices
  @share_table :bacview_device_share
  @topic "devices"
  @bbmd_collect_extra_ms 8_000
  @min_timeout 500
  @default_timeout 5_000
  @max_device_instance 4_194_303
  @max_vendor_id 65_535

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec default_timeout() :: pos_integer()
  def default_timeout(), do: @default_timeout

  @spec min_timeout() :: pos_integer()
  def min_timeout(), do: @min_timeout

  @doc """
  Parses and validates scan parameters from the UI.

  Supported keys: `"timeout_ms"` (minimum #{@min_timeout} ms), optional `"target_ip"`
  (plain IPv4 or octet ranges like `192.168.100.[31-35]`), optional `"device_id_low"` /
  `"device_id_high"` (0..#{@max_device_instance}), and optional `"vendor_id"` (0..#{@max_vendor_id}).
  """
  @spec parse_scan_params(map()) :: {:ok, keyword()} | {:error, term()}
  def parse_scan_params(params) when is_map(params) do
    with {:ok, timeout} <- parse_timeout(Map.get(params, "timeout_ms")),
         {:ok, destination} <- parse_destination(Map.get(params, "target_ip")),
         {:ok, low_limit} <- parse_device_id_limit(Map.get(params, "device_id_low")),
         {:ok, high_limit} <- parse_device_id_limit(Map.get(params, "device_id_high")),
         :ok <- validate_device_id_range(low_limit, high_limit),
         {:ok, vendor_id} <- parse_vendor_id(Map.get(params, "vendor_id")) do
      [timeout: timeout]
      |> maybe_put(:destination, destination)
      |> maybe_put(:low_limit, low_limit)
      |> maybe_put(:high_limit, high_limit)
      |> maybe_put(:vendor_id, vendor_id)
      |> then(&{:ok, &1})
    end
  end

  @spec scan(keyword()) :: {:ok, [map()]} | {:error, term()}
  def scan(opts \\ []) do
    GenServer.call(__MODULE__, {:scan, opts}, call_timeout(opts))
  end

  @doc """
  Starts a network scan without blocking the caller.

  Sends `{:scan_complete, {:ok, devices}}` or `{:scan_complete, {:error, reason}}`
  to `caller` when finished. Also broadcasts `{:devices_updated, devices}` on success.
  """
  @spec scan_async(pid(), keyword()) :: :ok
  def scan_async(caller, opts \\ []) when is_pid(caller) do
    GenServer.cast(__MODULE__, {:scan_async, caller, opts})
  end

  @doc """
  Cancels an in-flight scan (if any), clears discovered devices, and notifies
  subscribers. In-flight I-Am handlers and scan completion are ignored.
  """
  @spec cancel_scan() :: :ok
  def cancel_scan() do
    case Process.whereis(__MODULE__) do
      nil -> do_clear_devices()
      pid -> GenServer.cast(pid, :cancel_scan)
    end

    :ok
  end

  @doc false
  @spec clear_devices() :: :ok
  def clear_devices() do
    case Process.whereis(__MODULE__) do
      nil -> do_clear_devices()
      pid -> GenServer.cast(pid, :clear_devices)
    end

    :ok
  end

  @spec list_devices() :: [map()]
  def list_devices() do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, device} -> device end)
      |> Enum.sort_by(& &1.instance)
    end
  end

  @doc false
  @spec normalize_device_name(term()) :: String.t() | nil
  def normalize_device_name(value), do: do_normalize_device_name(value)

  @doc false
  @spec normalize_device_description(term()) :: String.t() | nil
  def normalize_device_description(value), do: do_normalize_device_name(value)

  @doc false
  @spec upsert_iam_device(IAm.t(), term(), term(), term()) :: map() | nil
  def upsert_iam_device(iam, address, npci_source \\ nil, source_address \\ nil),
    do: store_device(iam, address, npci_source, source_address)

  @doc false
  @spec apply_shared_source_max_concurrency() :: :ok
  def apply_shared_source_max_concurrency() do
    rebuild_share_indexes()
  end

  @doc false
  @spec shared_destination?(term()) :: boolean()
  def shared_destination?(address) do
    normalized = Address.normalize_destination(address)

    case share_ids(:address, normalized) do
      ids when is_map(ids) -> MapSet.size(ids) > 1
      _missing -> false
    end
  end

  @spec get_device(integer()) :: {:ok, map()} | :error
  def get_device(device_id) do
    if :ets.whereis(@table) == :undefined do
      :error
    else
      case :ets.lookup(@table, device_id) do
        [{^device_id, device}] -> {:ok, device}
        [] -> :error
      end
    end
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       scanning: false,
       last_scan_at: nil,
       pending_name_fetches: MapSet.new(),
       active_scan_gen: nil,
       scan_caller: nil,
       scan_generation: 0
     }}
  end

  @impl true
  def handle_call({:scan_active?, scan_gen}, _from, %{active_scan_gen: scan_gen} = state) do
    {:reply, true, state}
  end

  @impl true
  def handle_call({:scan_active?, _scan_gen}, _from, state) do
    {:reply, false, state}
  end

  @impl true
  def handle_call({:scan, _opts}, _from, %{scanning: true} = state) do
    {:reply, {:error, :already_scanning}, state}
  end

  @impl true
  def handle_call({:scan, opts}, _from, state) do
    {result, new_state} = run_scan(opts, state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_cast({:scan_async, caller, _opts}, %{scanning: true} = state) do
    send(caller, {:scan_complete, {:error, :already_scanning}})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:scan_async, caller, opts}, state) do
    scan_gen = state.scan_generation + 1

    Task.start(fn ->
      result =
        try do
          execute_scan(opts, scan_gen)
        rescue
          exception ->
            Logger.error("Discovery scan crashed: #{Exception.format(:error, exception)}")
            {:error, {:scan_failed, exception}}
        end

      GenServer.cast(__MODULE__, {:scan_finished, scan_gen, caller, result})
    end)

    {:noreply,
     %{
       state
       | scanning: true,
         scan_caller: caller,
         active_scan_gen: scan_gen,
         scan_generation: scan_gen
     }}
  end

  @impl true
  def handle_cast({:scan_finished, scan_gen, caller, result}, state) do
    if scan_gen == state.active_scan_gen do
      send(caller, {:scan_complete, result})

      {:noreply,
       %{
         state
         | scanning: false,
           scan_caller: nil,
           active_scan_gen: nil,
           last_scan_at: DateTime.utc_now()
       }}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:cancel_scan, state) do
    if state.scanning and is_pid(state.scan_caller) do
      send(state.scan_caller, {:scan_complete, {:error, :cancelled}})
    end

    do_clear_devices()

    {:noreply,
     %{
       state
       | scanning: false,
         scan_caller: nil,
         active_scan_gen: nil,
         scan_generation: state.scan_generation + 1,
         pending_name_fetches: MapSet.new()
     }}
  end

  @impl true
  def handle_cast(:clear_devices, state) do
    do_clear_devices()

    {:noreply, %{state | pending_name_fetches: MapSet.new()}}
  end

  @impl true
  def handle_cast(
        {:device_discovered, scan_gen, address, %IAm{} = iam, npci_source, source_address},
        state
      ) do
    if scan_gen == state.active_scan_gen and
         store_device(iam, address, npci_source, source_address) do
      broadcast_devices()
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:schedule_name_fetch, device_id}, state) do
    {:noreply, schedule_device_name_fetch_by_id(state, device_id)}
  end

  @impl true
  def handle_cast({:device_metadata_ready, device_id, name, description}, state) do
    state = %{state | pending_name_fetches: MapSet.delete(state.pending_name_fetches, device_id)}

    case get_device(device_id) do
      {:ok, device} ->
        updated =
          device
          |> maybe_put_metadata(:name, name)
          |> maybe_put_metadata(:description, description)

        if updated != device do
          :ets.insert(@table, {device_id, updated})
          broadcast_devices()
        end

      :error ->
        :ok
    end

    {:noreply, state}
  end

  defp run_scan(opts, state) do
    {execute_scan(opts), %{state | scanning: false, last_scan_at: DateTime.utc_now()}}
  end

  defp execute_scan(opts, scan_gen \\ nil) do
    with {:ok, timeout} <- validate_timeout(Keyword.get(opts, :timeout, @default_timeout)) do
      do_execute_scan(opts, timeout, scan_gen)
    end
  end

  defp do_execute_scan(opts, timeout, scan_gen) do
    low_limit = Keyword.get(opts, :low_limit)
    high_limit = Keyword.get(opts, :high_limit)
    vendor_id = Keyword.get(opts, :vendor_id)
    destination = Keyword.get(opts, :destination)

    who_is_opts =
      []
      |> maybe_put(:low_limit, low_limit)
      |> maybe_put(:high_limit, high_limit)
      |> maybe_put(:destination, destination)

    route = ForeignRegistration.scan_route()
    collect_timeout = collect_timeout(route, timeout)

    Logger.info(
      "Discovery scan starting (route: #{route}, collect: #{collect_timeout}ms, destination: #{format_destination(destination)}, opts: #{inspect(Keyword.drop(who_is_opts, [:destination]))})"
    )

    on_iam = fn address, %IAm{} = iam, npci_source, source_address ->
      if vendor_matches?(iam, vendor_id) do
        GenServer.cast(
          __MODULE__,
          {:device_discovered, scan_gen, address, iam, npci_source, source_address}
        )
      end
    end

    case IAmCollector.collect_while(
           fn -> send_who_is(who_is_opts) end,
           collect_timeout,
           on_iam: on_iam
         ) do
      {:ok, responses} ->
        if scan_active?(scan_gen) do
          devices =
            responses
            |> Enum.filter(fn {_address, %IAm{} = iam, _npci_source, _source_address} ->
              vendor_matches?(iam, vendor_id)
            end)
            |> Enum.map(fn {address, %IAm{} = iam, npci_source, source_address} ->
              store_device(iam, address, npci_source, source_address)
            end)
            |> Enum.reject(&is_nil/1)

          Logger.info("Discovery scan finished with #{length(devices)} device(s)")

          broadcast_devices()
          {:ok, list_devices()}
        else
          {:error, :cancelled}
        end

      {:error, _opts} = err ->
        err
    end
  end

  defp scan_active?(nil), do: true

  defp scan_active?(scan_gen) do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, {:scan_active?, scan_gen})
    end
  end

  defp collect_timeout(:bbmd, timeout), do: timeout + @bbmd_collect_extra_ms
  defp collect_timeout(_route, timeout), do: timeout

  defp send_who_is(opts) do
    case Keyword.get(opts, :destination) do
      destinations when is_list(destinations) ->
        Enum.reduce_while(destinations, :ok, fn destination, :ok ->
          case send_unicast_who_is(destination, opts) do
            :ok -> {:cont, :ok}
            {:error, _opts} = err -> {:halt, err}
          end
        end)

      nil ->
        broadcast_opts = Keyword.drop(opts, [:destination])

        case ForeignRegistration.broadcast_who_is(broadcast_opts) do
          :use_local ->
            Logger.debug("Who-Is via local broadcast")
            send_local_who_is(broadcast_opts)

          :ok ->
            :ok

          {:error, _opts} = err ->
            err
        end
    end
  end

  defp send_local_who_is(opts) do
    client = Client.stack_client()

    with {:ok, apdu} <- build_who_is_apdu(opts),
         {:ok, broadcast} <- GenServer.call(client, :get_broadcast_address) do
      StackClient.send(client, broadcast, apdu, [])
    end
  end

  defp send_unicast_who_is({ip, port}, opts) do
    client = Client.stack_client()

    with {:ok, apdu} <- build_who_is_apdu(opts),
         :ok <- StackClient.send(client, {ip, port}, apdu, []) do
      Logger.info("Who-Is unicast → #{Address.format_ip(ip)}:#{port}")
      :ok
    end
  end

  defp build_who_is_apdu(opts) do
    WhoIs.to_apdu(
      %WhoIs{
        device_id_low_limit: opts[:low_limit],
        device_id_high_limit: opts[:high_limit]
      },
      []
    )
  end

  defp call_timeout(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    route = ForeignRegistration.scan_route()
    collect_timeout(route, timeout) + 10_000
  end

  defp store_device(iam, address, npci_source, source_address)

  defp store_device(
         %IAm{device: %ObjectIdentifier{type: :device, instance: instance}} = iam,
         address,
         npci_source,
         source_address
       ) do
    normalized_address = Address.normalize_destination(address)
    %{ip: ip, port: port, label: address_label} = Address.destination_meta(normalized_address)

    incoming = %{
      id: instance,
      instance: instance,
      address: normalized_address,
      ip: ip,
      port: port,
      address_label: address_label,
      max_apdu: iam.max_apdu,
      segmentation: iam.segmentation_supported,
      vendor_id: iam.vendor_id,
      object: iam.device,
      discovered_at: DateTime.utc_now()
    }

    incoming =
      incoming
      |> maybe_put_npci_source(npci_source)
      |> maybe_put_source_address(source_address)

    previous =
      case :ets.lookup(@table, instance) do
        [{^instance, existing}] -> existing
        [] -> nil
      end

    device =
      case previous do
        nil -> new_discovered_device(incoming)
        existing -> merge_discovered_device(existing, incoming)
      end

    :ets.insert(@table, {instance, device})
    update_share_indexes(previous, device)
    GenServer.cast(__MODULE__, {:schedule_name_fetch, instance})
    device
  end

  defp store_device(%IAm{} = iam, _address, _npci_source, _source_address) do
    Logger.warning("Discovery ignored I-Am without device object identifier: #{inspect(iam)}")
    nil
  end

  defp new_discovered_device(incoming) do
    Map.merge(incoming, %{
      status: :discovered,
      object_count: nil,
      name: nil,
      description: nil,
      loaded_at: nil
    })
  end

  defp merge_discovered_device(existing, incoming) do
    if preserve_loaded_status?(existing, incoming) do
      Map.merge(incoming, %{
        status: :loaded,
        name: existing.name,
        description: Map.get(existing, :description),
        object_count: existing.object_count,
        loaded_at: existing.loaded_at
      })
    else
      new_discovered_device(incoming)
    end
  end

  defp preserve_loaded_status?(%{status: :loaded} = existing, incoming) do
    existing.id == incoming.id and
      Address.same_destination?(existing.address, incoming.address)
  end

  defp preserve_loaded_status?(_existing, _incoming), do: false

  defp maybe_put_npci_source(device, %BACnet.Protocol.NpciTarget{} = npci_source),
    do: Map.put(device, :npci_source, npci_source)

  defp maybe_put_npci_source(device, _npci_source), do: device

  defp maybe_put_source_address(device, source_address) when not is_nil(source_address) do
    Map.put(device, :source_address, Address.normalize_destination(source_address))
  end

  defp maybe_put_source_address(device, _source_address), do: device

  defp update_share_indexes(previous, device) do
    ensure_share_table()

    id = device.id
    prev_address = previous && Map.get(previous, :address)
    next_address = Map.get(device, :address)

    # Concurrency / invoke-id sharing is based on the *request destination*
    # (device.address), not the I-Am UDP source. BBMD discovery delivers every
    # I-Am from the BBMD IP, which must not serialize independent BACnet/IP peers.
    if prev_address != next_address do
      share_delete(:address, prev_address, id)
      share_put(:address, next_address, id)
    else
      share_put(:address, next_address, id)
    end

    [prev_address, next_address]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&refresh_shared_destination/1)
  end

  defp rebuild_share_indexes() do
    if :ets.whereis(@table) == :undefined do
      :ok
    else
      ensure_share_table()
      :ets.delete_all_objects(@share_table)

      devices = list_devices()

      Enum.each(devices, fn device ->
        share_put(:address, Map.get(device, :address), device.id)
      end)

      devices
      |> Enum.map(&Map.get(&1, :address))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.each(&refresh_shared_destination/1)

      :ok
    end
  end

  defp refresh_shared_destination(address) do
    ids = prune_share_ids(:address, address)
    shared? = MapSet.size(ids) > 1
    # Serialize property/object scan concurrency only when multiple devices are
    # addressed at the same transport destination (e.g. MS/TP gateway IP).
    max_concurrency = if shared?, do: 1, else: nil

    Enum.each(ids, fn id ->
      case get_device(id) do
        {:ok, device} ->
          updated =
            device
            |> put_shared_destination(shared?)
            |> put_device_max_concurrency(max_concurrency)

          if updated != device do
            :ets.insert(@table, {id, updated})
          end

        :error ->
          :ok
      end
    end)
  end

  defp prune_share_ids(kind, key) do
    ids =
      kind
      |> share_ids(key)
      |> Enum.filter(fn id -> match?({:ok, _device}, get_device(id)) end)
      |> MapSet.new()

    map_key = {kind, key}

    if MapSet.size(ids) == 0 do
      if :ets.whereis(@share_table) != :undefined, do: :ets.delete(@share_table, map_key)
    else
      :ets.insert(@share_table, {map_key, ids})
    end

    ids
  end

  defp put_device_max_concurrency(device, nil), do: Map.delete(device, :max_concurrency)

  defp put_device_max_concurrency(device, max_concurrency),
    do: Map.put(device, :max_concurrency, max_concurrency)

  defp put_shared_destination(device, true), do: Map.put(device, :shared_destination?, true)
  defp put_shared_destination(device, false), do: Map.delete(device, :shared_destination?)

  defp ensure_share_table() do
    if :ets.whereis(@share_table) == :undefined do
      :ets.new(@share_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  defp share_put(_kind, nil, _id), do: :ok

  defp share_put(kind, key, id) do
    ensure_share_table()
    map_key = {kind, key}
    ids = share_ids(kind, key)
    :ets.insert(@share_table, {map_key, MapSet.put(ids, id)})
  end

  defp share_delete(_kind, nil, _id), do: :ok

  defp share_delete(kind, key, id) do
    ensure_share_table()
    map_key = {kind, key}
    ids = MapSet.delete(share_ids(kind, key), id)

    if MapSet.size(ids) == 0 do
      :ets.delete(@share_table, map_key)
    else
      :ets.insert(@share_table, {map_key, ids})
    end
  end

  defp share_ids(kind, key) do
    if :ets.whereis(@share_table) == :undefined do
      MapSet.new()
    else
      case :ets.lookup(@share_table, {kind, key}) do
        [{_key, ids}] -> ids
        [] -> MapSet.new()
      end
    end
  end

  defp do_clear_devices() do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    if :ets.whereis(@share_table) != :undefined do
      :ets.delete_all_objects(@share_table)
    end

    broadcast_devices()
  end

  defp broadcast_devices() do
    Phoenix.PubSub.broadcast(BacView.PubSub, @topic, {:devices_updated, list_devices()})
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_timeout(nil), do: {:ok, @default_timeout}

  defp parse_timeout(value) when is_integer(value), do: validate_timeout(value)

  defp parse_timeout(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> validate_timeout(int)
      _nil -> {:error, :invalid_timeout}
    end
  end

  defp parse_timeout(_nil), do: {:error, :invalid_timeout}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= @min_timeout,
    do: {:ok, timeout}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout < @min_timeout,
    do: {:error, {:timeout_too_low, @min_timeout}}

  defp validate_timeout(_timeout), do: {:error, :invalid_timeout}

  defp parse_destination(nil), do: {:ok, nil}
  defp parse_destination(""), do: {:ok, nil}

  defp parse_destination(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      port = Settings.get().ipv4_port

      with {:ok, ips} <- Address.expand_scan_targets(trimmed) do
        {:ok, Enum.map(ips, &{&1, port})}
      end
    end
  end

  defp parse_destination(_nil), do: {:error, :invalid_host}

  defp parse_device_id_limit(nil), do: {:ok, nil}
  defp parse_device_id_limit(""), do: {:ok, nil}

  defp parse_device_id_limit(value) when is_integer(value), do: validate_device_id(value)

  defp parse_device_id_limit(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      case Integer.parse(trimmed) do
        {int, ""} -> validate_device_id(int)
        _nil -> {:error, :invalid_device_id}
      end
    end
  end

  defp parse_device_id_limit(_nil), do: {:error, :invalid_device_id}

  defp validate_device_id(id) when is_integer(id) and id >= 0 and id <= @max_device_instance,
    do: {:ok, id}

  defp validate_device_id(_id), do: {:error, :invalid_device_id}

  defp validate_device_id_range(low, high)
       when is_nil(low) or is_nil(high) or low <= high,
       do: :ok

  defp validate_device_id_range(_low, _high), do: {:error, :invalid_device_range}

  defp parse_vendor_id(nil), do: {:ok, nil}
  defp parse_vendor_id(""), do: {:ok, nil}

  defp parse_vendor_id(value) when is_integer(value), do: validate_vendor_id(value)

  defp parse_vendor_id(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      case Integer.parse(trimmed) do
        {int, ""} -> validate_vendor_id(int)
        _nil -> {:error, :invalid_vendor_id}
      end
    end
  end

  defp parse_vendor_id(_nil), do: {:error, :invalid_vendor_id}

  defp validate_vendor_id(id) when is_integer(id) and id >= 0 and id <= @max_vendor_id,
    do: {:ok, id}

  defp validate_vendor_id(_id), do: {:error, :invalid_vendor_id}

  defp vendor_matches?(%IAm{vendor_id: vendor_id}, filter_vendor_id)
       when is_integer(filter_vendor_id),
       do: vendor_id == filter_vendor_id

  defp vendor_matches?(_iam, _filter_vendor_id), do: true

  defp format_destination(destinations) when is_list(destinations) do
    ips = Enum.map(destinations, fn {ip, _port} -> Address.format_ip(ip) end)

    case ips do
      [ip] ->
        ip

      _destinations ->
        "#{length(ips)} targets (#{Enum.join(Enum.take(ips, 3), ", ")}#{if length(ips) > 3, do: ", …", else: ""})"
    end
  end

  defp format_destination(nil), do: "broadcast"

  defp schedule_device_name_fetch_by_id(state, device_id) do
    if MapSet.member?(state.pending_name_fetches, device_id) do
      state
    else
      case get_device(device_id) do
        {:ok, %{name: name}} when not is_nil(name) ->
          state

        {:ok, device} ->
          Task.start(fn -> fetch_device_name_async(device) end)

          %{
            state
            | pending_name_fetches: MapSet.put(state.pending_name_fetches, device_id)
          }

        :error ->
          state
      end
    end
  end

  defp fetch_device_name_async(device) do
    name = read_device_object_property(device, :object_name, &do_normalize_device_name/1)
    description = read_device_object_property(device, :description, &do_normalize_device_name/1)
    GenServer.cast(__MODULE__, {:device_metadata_ready, device.id, name, description})
  end

  defp read_device_object_property(
         %{id: device_id, address: address, object: object},
         property,
         normalize
       ) do
    case PropertyReader.read_property_value(
           Client,
           address,
           object,
           property,
           remote_device_id: device_id,
           log_errors: false
         ) do
      {:ok, value} ->
        normalize.(value)

      {:error, reason} ->
        Logger.debug(
          "Discovery could not read #{property} for device #{device_id}: #{inspect(reason)}"
        )

        nil
    end
  end

  defp maybe_put_metadata(device, _key, nil), do: device
  defp maybe_put_metadata(device, _key, ""), do: device

  defp maybe_put_metadata(device, key, value) when is_binary(value),
    do: Map.put(device, key, value)

  defp do_normalize_device_name(%Encoding{value: value}), do: do_normalize_device_name(value)

  defp do_normalize_device_name(name) when is_binary(name) do
    case Text.sanitize_utf8(name) do
      "" -> nil
      sanitized -> sanitized
    end
  end

  defp do_normalize_device_name(name) when not is_nil(name) do
    name |> to_string() |> do_normalize_device_name()
  end

  defp do_normalize_device_name(_do_normalize_device_name), do: nil
end
