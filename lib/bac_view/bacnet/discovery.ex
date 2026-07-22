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
  alias BacView.BACnet.Cache
  alias BacView.BACnet.Client
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.DeviceSessionSupervisor
  alias BacView.BACnet.ForeignRegistration
  alias BacView.BACnet.IAmCollector
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.Settings
  alias BacView.Text

  @table :bacview_devices
  @share_table :bacview_device_share
  @topic "devices"
  @topic_cov "cov:updates"
  @topic_alarms "alarms:updates"
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

  @type acceptance_filters :: %{
          low_limit: non_neg_integer() | nil,
          high_limit: non_neg_integer() | nil,
          vendor_id: non_neg_integer() | nil
        }

  # Stored in app env so filters work even when the Discovery GenServer is not
  # started (e.g. `config :bacview, start_bacnet: false` in tests).
  @acceptance_filters_env_key :discovery_acceptance_filters

  @doc """
  Returns the current device acceptance filters (scan panel device-ID range + vendor).
  """
  @spec acceptance_filters() :: acceptance_filters()
  def acceptance_filters() do
    case Application.get_env(:bacview, @acceptance_filters_env_key) do
      %{} = filters -> normalize_acceptance_filters(filters)
      _missing -> default_acceptance_filters()
    end
  end

  @doc """
  Updates filters used when adding **new** devices (I-Am, restart COV, etc.).

  Accepts the same keys as scan opts: `:low_limit`, `:high_limit`, `:vendor_id`.
  """
  @spec set_acceptance_filters(keyword() | map()) :: :ok
  def set_acceptance_filters(opts) when is_list(opts) or is_map(opts) do
    filters = normalize_acceptance_filters(opts)
    Application.put_env(:bacview, @acceptance_filters_env_key, filters)
    :ok
  end

  @doc """
  True when a **new** device with the given instance and vendor may be added.

  Existing devices in the list are never rejected by this check.
  """
  @spec accepts_new_device?(integer(), term(), acceptance_filters() | nil) :: boolean()
  def accepts_new_device?(instance, vendor_id, filters \\ nil)

  def accepts_new_device?(instance, vendor_id, nil) when is_integer(instance) do
    accepts_new_device?(instance, vendor_id, acceptance_filters())
  end

  def accepts_new_device?(instance, vendor_id, filters)
      when is_integer(instance) and is_map(filters) do
    instance_accepted?(instance, filters) and vendor_accepted?(vendor_id, filters)
  end

  def accepts_new_device?(_instance, _vendor_id, _filters), do: false

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
  Cancels an in-flight scan (if any), purges all discovered device data, and
  notifies subscribers. In-flight I-Am handlers and scan completion are ignored.

  Same data wipe as `clear_devices/0` (sessions stopped, ETS caches emptied).
  """
  @spec cancel_scan() :: :ok
  def cancel_scan() do
    case Process.whereis(__MODULE__) do
      nil -> do_clear_devices()
      pid -> GenServer.cast(pid, :cancel_scan)
    end

    :ok
  end

  @doc """
  Purges every discovered device and all associated scanned data.

  Stops all `DeviceSession` processes and clears device-related ETS tables
  (objects, properties, hierarchy, subscriptions, events, skip modes, etc.) so
  a later Who-Is rediscovery starts from a cold cache.
  """
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

  @doc """
  Ensures a minimal device entry exists so `DeviceSession` can load it.

  Used when a device restart COV arrives before an I-Am has been stored.
  """
  @spec ensure_discovered_device(ObjectIdentifier.t(), term()) :: {:ok, map()} | :error
  def ensure_discovered_device(
        %ObjectIdentifier{type: :device, instance: instance} = object,
        address
      )
      when is_integer(instance) do
    if :ets.whereis(@table) == :undefined do
      :error
    else
      normalized_address = Address.normalize_destination(address)
      %{ip: ip, port: port, label: address_label} = Address.destination_meta(normalized_address)

      case get_device(instance) do
        {:ok, device} ->
          refresh_discovered_device_address(
            device,
            object,
            normalized_address,
            ip,
            port,
            address_label
          )

        :error ->
          # Unknown device: Who-Is → I-Am, then acceptance filters (device ID + vendor).
          discover_unknown_device_via_who_is(instance, normalized_address)
      end
    end
  end

  def ensure_discovered_device(_object, _address), do: :error

  # Unsolicited restart COV (or similar) for a device we have never listed.
  # Probe with a targeted Who-Is so vendor / max_apdu come from the real I-Am and
  # scan-panel filters can be applied before the device appears in the UI.
  @who_is_probe_timeout_ms 3_000

  defp discover_unknown_device_via_who_is(instance, address) do
    filters = acceptance_filters()

    if instance_accepted?(instance, filters) do
      case probe_device_iam(instance, address) do
        {:ok, iam, resolved_address, npci_source, source_address} ->
          case store_device(iam, resolved_address, npci_source, source_address) do
            %{} = device ->
              {:ok, device}

            nil ->
              Logger.debug(
                "Discovery rejected new device #{instance} after I-Am: does not match scan panel filters"
              )

              :error
          end

        {:error, reason} ->
          Logger.debug(
            "Discovery Who-Is probe failed for unknown device #{instance}: #{inspect(reason)}"
          )

          :error
      end
    else
      Logger.debug(
        "Discovery rejected new device #{instance}: outside scan panel device-ID filter"
      )

      :error
    end
  end

  defp probe_device_iam(instance, address) do
    probe = Application.get_env(:bacview, :device_iam_probe, &default_device_iam_probe/2)
    probe.(instance, address)
  end

  defp default_device_iam_probe(instance, address) do
    opts = [
      destination: [address],
      low_limit: instance,
      high_limit: instance
    ]

    case IAmCollector.collect_while(fn -> send_who_is(opts) end, @who_is_probe_timeout_ms) do
      {:ok, responses} ->
        match =
          Enum.find_value(responses, fn
            {addr, %IAm{device: %{instance: ^instance}} = iam, npci_source, source_address} ->
              {:ok, iam, addr, npci_source, source_address}

            {_addr, %IAm{}, _npci, _src} ->
              nil

            # collect_while typespec mentions 2-tuples; accept either shape
            {addr, %IAm{device: %{instance: ^instance}} = iam} ->
              {:ok, iam, addr, nil, nil}

            _other ->
              nil
          end)

        match || {:error, :no_iam}

      {:error, _reason} = err ->
        err
    end
  end

  defp refresh_discovered_device_address(
         device,
         object,
         normalized_address,
         ip,
         port,
         address_label
       ) do
    same_address? = Address.same_destination?(Map.get(device, :address), normalized_address)
    same_object? = Map.get(device, :object) == object

    if same_address? and same_object? do
      {:ok, device}
    else
      previous = device

      updated =
        device
        |> Map.put(:address, normalized_address)
        |> Map.put(:ip, ip)
        |> Map.put(:port, port)
        |> Map.put(:address_label, address_label)
        |> Map.put(:object, object)

      :ets.insert(@table, {device.id, updated})
      update_share_indexes(previous, updated)
      broadcast_devices()
      {:ok, updated}
    end
  end

  @doc """
  Starts a device scan when "scan devices as they come online" is enabled.

  * Default: scan only when the device is not already loaded and no load is in progress.
  * `force: true`: reload even when already loaded (e.g. device restart COV).
  """
  @spec maybe_scan_device_online(integer(), keyword()) :: :ok
  def maybe_scan_device_online(device_id, opts \\ []) when is_integer(device_id) do
    force? = Keyword.get(opts, :force, false)

    if Settings.scan_on_online?() and not DeviceSession.loading?(device_id) do
      cond do
        force? ->
          start_online_scan(device_id, :reload)

        device_loaded?(device_id) ->
          :ok

        true ->
          start_online_scan(device_id, :load)
      end
    end

    :ok
  end

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

  def handle_call({:scan_active?, _scan_gen}, _from, state) do
    {:reply, false, state}
  end

  def handle_call({:scan, _opts}, _from, %{scanning: true} = state) do
    {:reply, {:error, :already_scanning}, state}
  end

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

    # Keep acceptance filters in sync with the active scan panel criteria.
    set_acceptance_filters(
      low_limit: low_limit,
      high_limit: high_limit,
      vendor_id: vendor_id
    )

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
      if accepts_iam?(iam, low_limit, high_limit, vendor_id) do
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
              accepts_iam?(iam, low_limit, high_limit, vendor_id)
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

  defp send_unicast_who_is(destination, opts) do
    client = Client.stack_client()

    with {:ok, apdu} <- build_who_is_apdu(opts),
         :ok <- StackClient.send(client, destination, apdu, []) do
      Logger.info("Who-Is unicast → #{format_single_destination(destination)}")
      :ok
    end
  end

  defp format_single_destination({ip, port}) when is_tuple(ip) and is_integer(port),
    do: "#{Address.format_ip(ip)}:#{port}"

  defp format_single_destination(other), do: Address.format_destination(other)

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

    case previous do
      nil ->
        if accepts_new_device?(instance, iam.vendor_id) do
          device = new_discovered_device(incoming)
          :ets.insert(@table, {instance, device})
          update_share_indexes(nil, device)
          GenServer.cast(__MODULE__, {:schedule_name_fetch, instance})
          maybe_scan_device_online(instance)
          device
        else
          Logger.debug(
            "Discovery ignored new I-Am for device #{instance} (vendor=#{inspect(iam.vendor_id)}): " <>
              "does not match scan panel filters"
          )

          nil
        end

      existing ->
        device = merge_discovered_device(existing, incoming)
        :ets.insert(@table, {instance, device})
        update_share_indexes(previous, device)
        GenServer.cast(__MODULE__, {:schedule_name_fetch, instance})
        maybe_scan_device_online(instance)
        device
    end
  end

  defp store_device(%IAm{} = iam, _address, _npci_source, _source_address) do
    Logger.warning("Discovery ignored I-Am without device object identifier: #{inspect(iam)}")
    nil
  end

  defp device_loaded?(device_id) do
    case get_device(device_id) do
      {:ok, %{status: :loaded}} -> true
      _other -> false
    end
  end

  defp start_online_scan(device_id, mode) when mode in [:load, :reload] do
    Task.start(fn ->
      result =
        case mode do
          :load -> DeviceSession.load(device_id)
          :reload -> DeviceSession.reload(device_id)
        end

      case result do
        {:ok, _loaded} ->
          Logger.info("Scanned device #{device_id} as it came online (#{mode})")

        {:error, reason} ->
          Logger.debug(
            "Scan-on-online failed for device #{device_id} (#{mode}): #{inspect(reason)}"
          )
      end
    end)

    :ok
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
    if preserve_device_status?(existing, incoming) do
      Map.merge(incoming, %{
        status: existing.status,
        name: existing.name,
        description: Map.get(existing, :description),
        object_count: existing.object_count,
        loaded_at: existing.loaded_at
      })
    else
      new_discovered_device(incoming)
    end
  end

  # Keep loaded/loading when the same device I-Ams again (do not flash back to "Entdeckt").
  defp preserve_device_status?(%{status: status} = existing, incoming)
       when status in [:loaded, :loading] do
    existing.id == incoming.id and
      Address.same_destination?(existing.address, incoming.address)
  end

  defp preserve_device_status?(_existing, _incoming), do: false

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
    if concurrency_shared_reduction?() do
      ids = prune_share_ids(:address, address)
      shared? = MapSet.size(ids) > 1
      # Serialize property/object scan concurrency only when multiple devices are
      # addressed at the same transport destination (e.g. MS/TP gateway IP).
      max_concurrency = if(shared?, do: 1)

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
    if concurrency_shared_reduction?() do
      ensure_share_table()
      map_key = {kind, key}
      ids = share_ids(kind, key)
      :ets.insert(@share_table, {map_key, MapSet.put(ids, id)})
    else
      :ok
    end
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
    # Stop sessions first so in-flight loads cannot re-insert into ETS after wipe.
    DeviceSessionSupervisor.stop_all()
    Cache.clear_all_device_data()
    broadcast_devices()
    broadcast_cleared_side_channels()
  end

  defp broadcast_devices() do
    Phoenix.PubSub.broadcast(BacView.PubSub, @topic, {:devices_updated, list_devices()})
  end

  defp broadcast_cleared_side_channels() do
    Phoenix.PubSub.broadcast(BacView.PubSub, @topic_cov, :cov_updated)
    Phoenix.PubSub.broadcast(BacView.PubSub, @topic_alarms, :alarms_updated)
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

  defp accepts_iam?(%IAm{device: %ObjectIdentifier{instance: instance}} = iam, low, high, vendor) do
    accepts_new_device?(
      instance,
      iam.vendor_id,
      %{low_limit: low, high_limit: high, vendor_id: vendor}
    )
  end

  defp accepts_iam?(_iam, _low, _high, _vendor), do: false

  defp default_acceptance_filters() do
    %{low_limit: nil, high_limit: nil, vendor_id: nil}
  end

  defp normalize_acceptance_filters(opts) when is_list(opts) do
    normalize_acceptance_filters(Map.new(opts))
  end

  defp normalize_acceptance_filters(opts) when is_map(opts) do
    %{
      low_limit: filter_int(Map.get(opts, :low_limit) || Map.get(opts, "low_limit")),
      high_limit: filter_int(Map.get(opts, :high_limit) || Map.get(opts, "high_limit")),
      vendor_id: filter_int(Map.get(opts, :vendor_id) || Map.get(opts, "vendor_id"))
    }
  end

  defp filter_int(nil), do: nil
  defp filter_int(value) when is_integer(value), do: value

  defp filter_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp filter_int(_value), do: nil

  defp instance_accepted?(_instance, %{low_limit: nil, high_limit: nil}), do: true

  defp instance_accepted?(instance, %{low_limit: low, high_limit: high})
       when is_integer(instance) do
    min_id = if is_integer(low), do: low, else: 0
    max_id = if is_integer(high), do: high, else: @max_device_instance
    instance >= min_id and instance <= max_id
  end

  defp vendor_accepted?(_vendor_id, %{vendor_id: nil}), do: true

  defp vendor_accepted?(vendor_id, %{vendor_id: required})
       when is_integer(required) and is_integer(vendor_id),
       do: vendor_id == required

  # Unknown vendor while a filter is active → reject (do not show until verified).
  defp vendor_accepted?(_vendor_id, %{vendor_id: required}) when is_integer(required), do: false

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

  defp concurrency_shared_reduction?() do
    not Application.get_env(
      :bacview,
      :property_read_concurrency_disable_shared_reduction,
      false
    )
  end
end
