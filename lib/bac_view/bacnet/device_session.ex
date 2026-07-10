defmodule BacView.BACnet.DeviceSession do
  @moduledoc """
  Per-device GenServer: caches objects and properties for one BACnet device.
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.EventTimestamps
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.Client
  alias BacView.BACnet.DeviceSessionSupervisor
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.HierarchyBuilder
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.BACnet.Protocol.PropertyWriter
  alias BacView.BACnet.Protocol.StatusFlagsParser
  alias BacView.BACnet.Protocol.TrendLogNavigation
  alias BacView.BACnet.Segmentation
  alias BacView.MapHelpers

  @objects_table :bacview_objects
  @properties_table :bacview_properties
  @devices_table :bacview_devices

  def start_link(device_id) when is_integer(device_id) do
    GenServer.start_link(__MODULE__, device_id, name: DeviceSessionSupervisor.via(device_id))
  end

  @spec load(integer()) :: {:ok, map()} | {:error, term()}
  def load(device_id) do
    with {:ok, pid} <- DeviceSessionSupervisor.ensure_session(device_id) do
      GenServer.call(pid, :load, 120_000)
    end
  end

  @doc "Forces a fresh BACnet read even when the session is already loaded."
  @spec reload(integer()) :: {:ok, map()} | {:error, term()}
  def reload(device_id) do
    with {:ok, pid} <- DeviceSessionSupervisor.ensure_session(device_id) do
      GenServer.call(pid, :reload, 120_000)
    end
  end

  @spec objects(integer()) :: [map()]
  def objects(device_id) do
    case GenServer.whereis(DeviceSessionSupervisor.via(device_id)) do
      nil -> []
      pid -> GenServer.call(pid, :objects)
    end
  end

  @spec read_properties(integer(), ObjectIdentifier.t()) :: {:ok, [map()]} | {:error, term()}
  def read_properties(device_id, %ObjectIdentifier{} = object) do
    with {:ok, pid} <- DeviceSessionSupervisor.ensure_session(device_id) do
      GenServer.call(pid, {:read_properties, object}, 60_000)
    end
  end

  @spec read_property(
          integer(),
          ObjectIdentifier.t(),
          atom() | integer(),
          keyword()
        ) :: {:ok, term()} | {:error, term()}
  def read_property(device_id, %ObjectIdentifier{} = object, property, opts \\ []) do
    with {:ok, pid} <- DeviceSessionSupervisor.ensure_session(device_id) do
      GenServer.call(pid, {:read_property, object, property, opts}, 60_000)
    end
  end

  @spec read_range(
          integer(),
          ObjectIdentifier.t(),
          atom() | integer(),
          term(),
          keyword()
        ) :: {:ok, term()} | {:error, term()}
  def read_range(device_id, %ObjectIdentifier{} = object, property, range, opts \\ []) do
    with {:ok, pid} <- DeviceSessionSupervisor.ensure_session(device_id) do
      GenServer.call(pid, {:read_range, object, property, range, opts}, 120_000)
    end
  end

  @spec write_property(
          integer(),
          ObjectIdentifier.t(),
          atom() | integer(),
          term(),
          keyword()
        ) :: :ok | {:error, term()}
  def write_property(device_id, %ObjectIdentifier{} = object, property, value, opts \\ []) do
    with {:ok, pid} <- DeviceSessionSupervisor.ensure_session(device_id) do
      GenServer.call(pid, {:write_property, object, property, value, opts}, 60_000)
    end
  end

  @spec hierarchy(integer()) :: map()
  def hierarchy(device_id) do
    case GenServer.whereis(DeviceSessionSupervisor.via(device_id)) do
      nil -> HierarchyBuilder.build([], [])
      pid -> GenServer.call(pid, :hierarchy)
    end
  end

  @spec apply_cov_update(
          integer(),
          ObjectIdentifier.t(),
          atom() | integer(),
          term(),
          String.t()
        ) :: :ok
  def apply_cov_update(device_id, object_id, property, value, formatted) do
    case GenServer.whereis(DeviceSessionSupervisor.via(device_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:cov_update, object_id, property, value, formatted})
    end
  end

  @spec publish_property_update(integer(), ObjectIdentifier.t(), atom() | integer(), term()) ::
          :ok
  def publish_property_update(device_id, %ObjectIdentifier{} = object_id, property, value) do
    case GenServer.whereis(DeviceSessionSupervisor.via(device_id)) do
      nil ->
        :ok

      pid ->
        GenServer.cast(pid, {:publish_property_update, object_id, property, value})
        :ok
    end
  end

  @spec get_properties(integer(), ObjectIdentifier.t()) :: [map()]
  def get_properties(device_id, object) do
    key = property_key(device_id, object)

    case :ets.lookup(@properties_table, key) do
      [{^key, props}] -> props
      [] -> []
    end
  end

  @impl true
  def init(device_id) do
    {:ok,
     %{
       device_id: device_id,
       device: nil,
       objects: [],
       hierarchy: %{roots: [], empty?: true, structured_view_count: 0},
       status: :idle,
       load_waiters: []
     }}
  end

  @impl true
  def handle_call(:load, _from, %{status: :ready, device: device} = state)
      when not is_nil(device) do
    {:reply, {:ok, loaded_snapshot(state)}, state}
  end

  def handle_call(:load, from, %{status: :loading, load_waiters: waiters} = state) do
    {:noreply, %{state | load_waiters: [from | waiters]}}
  end

  def handle_call(:load, from, state) do
    send(self(), :fetch_device)
    {:noreply, %{state | status: :loading, load_waiters: [from]}}
  end

  def handle_call(:reload, from, %{status: :loading, load_waiters: waiters} = state) do
    {:noreply, %{state | load_waiters: [from | waiters]}}
  end

  def handle_call(:reload, from, state) do
    send(self(), :fetch_device)
    {:noreply, %{state | status: :loading, load_waiters: [from]}}
  end

  def handle_call(:objects, _from, %{objects: objects} = state) do
    {:reply, objects, state}
  end

  @impl true
  def handle_call(:hierarchy, _from, %{hierarchy: hierarchy} = state) do
    {:reply, hierarchy, state}
  end

  @impl true
  def handle_call(
        {:read_properties, object},
        _from,
        %{device_id: device_id, device: device} = state
      ) do
    {result, state} =
      if device do
        case safe_read_properties(device.address, object) do
          {:ok, props} ->
            :ets.insert(@properties_table, {property_key(device_id, object), props})

            state =
              state
              |> Map.update!(:objects, &sync_object_fields_from_properties(&1, object, props))
              |> sync_objects_cache()

            {{:ok, props}, state}

          {:error, _load} = err ->
            {err, state}
        end
      else
        {{:error, :device_not_loaded}, state}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:read_property, object, property, opts},
        _from,
        %{device: device} = state
      ) do
    result =
      if device do
        Client.read_property(device.address, object, property, opts)
      else
        {:error, :device_not_loaded}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:read_range, object, property, range, opts},
        _from,
        %{device: device} = state
      ) do
    result =
      if device do
        Client.read_range(device.address, object, property, range, opts)
      else
        {:error, :device_not_loaded}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:write_property, object, property, value, opts},
        _from,
        %{device: device} = state
      ) do
    result =
      if device do
        Client.write_property(device.address, object, property, value, opts)
      else
        {:error, :device_not_loaded}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:fetch_device, state) do
    case fetch_device(state) do
      {:ok, loaded, new_state} ->
        reply_waiters(new_state.load_waiters, {:ok, loaded})
        {:noreply, %{new_state | load_waiters: []}}

      {:error, reason, new_state} ->
        reply_waiters(new_state.load_waiters, {:error, reason})
        {:noreply, %{new_state | load_waiters: []}}
    end
  end

  @impl true
  def handle_cast({:cov_update, object_id, property, value, formatted}, state) do
    {:noreply, apply_property_update(state, object_id, property, value, formatted)}
  end

  @impl true
  def handle_cast({:publish_property_update, object_id, property, value}, state) do
    obj = find_cached_object(state.objects, object_id)
    formatted = format_published_property(property, value, obj)
    new_state = apply_property_update(state, object_id, property, value, formatted)

    broadcast_property_update(new_state.device_id, object_id, property, value, formatted)

    {:noreply, new_state}
  end

  defp fetch_device(%{device_id: device_id} = state) do
    with {:ok, device} <- Discovery.get_device(device_id),
         {:ok, loaded} <- load_device(device) do
      update_device_meta(device_id, loaded)

      new_state = %{
        state
        | device: loaded,
          objects: loaded.objects,
          hierarchy: loaded.hierarchy,
          status: :ready
      }

      {:ok, loaded, new_state}
    else
      :error -> {:error, :device_not_found, %{state | status: :error}}
      {:error, reason} -> {:error, reason, %{state | status: :error}}
    end
  end

  defp reply_waiters(waiters, reply) do
    Enum.each(waiters, &GenServer.reply(&1, reply))
  end

  defp safe_read_properties(address, object) do
    PropertyReader.read_all(Client, address, object)
  rescue
    exception -> {:error, {:property_read_failed, exception}}
  catch
    :exit, reason -> {:error, {:property_read_failed, reason}}
  end

  defp load_device(%{id: device_id, address: address, object: device_obj} = discovered) do
    report_progress(device_id, %{stage: :reading_device, done: 0, total: nil})

    load_device_impl(discovered, device_id, address, device_obj)
  catch
    :exit, reason ->
      Logger.error("Device #{device_id} load exited: #{inspect(reason)}")
      {:error, {:load_failed, reason}}
  end

  defp load_device_impl(discovered, device_id, address, device_obj) do
    with {:ok, device} <-
           read_object_fallback(address, device_obj, allow_unknown_properties: true),
         {:ok, object_ids} <- read_object_list(address, device_obj, device_id),
         {:ok, scanned} <- scan_object_list(device_id, address, device_obj, object_ids) do
      scanned_len = length(scanned)

      report_progress(device_id, %{
        stage: :building_hierarchy,
        done: scanned_len,
        total: scanned_len
      })

      objects =
        scanned
        |> Enum.map(&summarize_object/1)
        |> Enum.sort_by(fn obj -> {obj.type, obj.instance} end)

      hierarchy = HierarchyBuilder.build(scanned, objects)

      :ets.insert(@objects_table, {discovered.id, objects})
      :ets.insert(:bacview_hierarchy, {discovered.id, hierarchy})

      loaded =
        Map.merge(discovered, %{
          name: Map.get(device, :object_name),
          object_count: length(objects),
          status: :loaded,
          loaded_at: DateTime.utc_now(),
          objects: objects,
          hierarchy: hierarchy
        })

      {:ok, loaded}
    end
  end

  defp read_object_list(address, device_obj, device_id) do
    report_progress(device_id, %{stage: :reading_object_list, done: 0, total: nil})

    case Client.read_property(address, device_obj, :object_list, raw: true) do
      {:ok, raw} ->
        object_ids = normalize_object_ids(raw)

        report_progress(device_id, %{
          stage: :reading_object_list,
          done: 0,
          total: length(object_ids)
        })

        {:ok, object_ids}

      {:error, _address} = err ->
        if Segmentation.fallback_error?(err) do
          read_object_list_indexed(address, device_obj, device_id)
        else
          err
        end
    end
  end

  # Fallback for devices that do not support segmentation: the object_list array
  # response may be too large. Read the length (index 0), then fetch each element
  # by array index individually (each response is a single small ObjectIdentifier).
  defp read_object_list_indexed(address, device_obj, device_id) do
    case Client.read_property(address, device_obj, :object_list, array_index: 0) do
      {:ok, count} when is_integer(count) ->
        if count == 0 do
          {:ok, []}
        else
          report_progress(device_id, %{
            stage: :reading_object_list,
            done: 0,
            total: count
          })

          processed_counter = :counters.new(1, [])

          ids =
            1..count
            |> Task.async_stream(
              fn idx ->
                oid =
                  case Client.read_property(
                         address,
                         device_obj,
                         :object_list,
                         array_index: idx,
                         raw: true
                       ) do
                    {:ok, %Encoding{value: %ObjectIdentifier{} = oid}} ->
                      oid

                    {:ok, %ObjectIdentifier{} = oid} ->
                      oid

                    {:error, reason} ->
                      Logger.warning(
                        "Failed to read object_list index #{idx}: #{inspect(reason)}"
                      )

                      nil

                    other ->
                      Logger.warning("Failed to read object_list index #{idx}: #{inspect(other)}")
                      nil
                  end

                bump_object_list_progress(device_id, processed_counter, count)
                oid
              end,
              max_concurrency: 8,
              timeout: :infinity,
              ordered: false
            )
            |> Enum.reduce([], fn
              {:ok, %ObjectIdentifier{} = oid}, acc ->
                [oid | acc]

              {:ok, nil}, acc ->
                acc

              {:exit, reason}, acc ->
                Logger.warning("object_list index read exited: #{inspect(reason)}")
                acc

              other, acc ->
                Logger.warning("Unexpected object_list stream result: #{inspect(other)}")
                acc
            end)
            |> Enum.reverse()

          report_progress(device_id, %{
            stage: :reading_object_list,
            done: count,
            total: count
          })

          {:ok, ids}
        end

      {:error, _address} = err ->
        err

      _address ->
        {:error, :object_list_not_readable}
    end
  end

  defp scan_object_list(device_id, address, device_obj, object_ids) do
    total = length(object_ids)

    report_progress(device_id, %{
      stage: :scanning_objects,
      done: 0,
      total: total,
      errors: 0,
      skipped: 0
    })

    if total == 0 do
      {:ok, []}
    else
      scan_opts = [
        allow_unknown_properties: true,
        remote_device_id: device_obj.instance,
        skip_property_validation_remote_object: true
      ]

      done_counter = :counters.new(1, [])
      error_counter = :counters.new(1, [])
      skip_counter = :counters.new(1, [])

      {scanned, error_log} =
        object_ids
        |> Task.async_stream(
          fn object_id ->
            case read_object_fallback(address, object_id, scan_opts) do
              {:ok, obj} -> {:ok, {object_id, obj}}
              {:error, :unsupported_object_type} -> {:skipped, object_id}
              {:error, reason} -> {:error, object_id, reason}
            end
          end,
          max_concurrency: min(32, System.schedulers_online()),
          ordered: false,
          timeout: :infinity
        )
        |> Enum.reduce({[], []}, fn
          {:ok, {:ok, pair}}, {acc, error_log} ->
            bump_scan_progress(
              device_id,
              done_counter,
              error_counter,
              skip_counter,
              total,
              pair,
              error_log
            )

            {[pair | acc], error_log}

          {:ok, {:skipped, object_id}}, {acc, error_log} ->
            :counters.add(skip_counter, 1, 1)

            bump_scan_progress(
              device_id,
              done_counter,
              error_counter,
              skip_counter,
              total,
              object_id,
              error_log
            )

            {acc, error_log}

          {:ok, {:error, object_id, reason}}, {acc, error_log} ->
            Logger.warning(
              "Failed to read object #{format_current_object(object_id)}: #{inspect(reason)}"
            )

            :counters.add(error_counter, 1, 1)

            error_log = prepend_scan_error(error_log, object_id, reason)

            bump_scan_progress(
              device_id,
              done_counter,
              error_counter,
              skip_counter,
              total,
              nil,
              error_log
            )

            {acc, error_log}

          {:exit, exit_reason}, {acc, error_log} ->
            Logger.warning("Object read task exited: #{inspect(exit_reason)}")
            :counters.add(error_counter, 1, 1)

            error_log = prepend_scan_error(error_log, nil, exit_reason)

            bump_scan_progress(
              device_id,
              done_counter,
              error_counter,
              skip_counter,
              total,
              nil,
              error_log
            )

            {acc, error_log}

          other, {acc, error_log} ->
            Logger.warning("Unexpected object read stream result: #{inspect(other)}")
            :counters.add(error_counter, 1, 1)

            error_log = prepend_scan_error(error_log, nil, other)

            bump_scan_progress(
              device_id,
              done_counter,
              error_counter,
              skip_counter,
              total,
              nil,
              error_log
            )

            {acc, error_log}
        end)

      scanned = Enum.reverse(scanned)
      error_log = Enum.reverse(error_log)

      report_progress(device_id, %{
        stage: :scanning_objects,
        done: total,
        total: total,
        errors: :counters.get(error_counter, 1),
        skipped: :counters.get(skip_counter, 1),
        error_log: error_log
      })

      {:ok, scanned}
    end
  end

  # Reads an object, using ReadPropertyMultiple when possible. If the device
  # returns a segmentation_not_supported error (some devices do not support
  # segmentation and large RPM responses will fail), falls back to reading
  # relevant properties one-by-one using single ReadProperty requests.
  defp read_object_fallback(address, %ObjectIdentifier{} = object, opts) do
    case Client.read_object(address, object, opts) do
      {:ok, obj} ->
        {:ok, obj}

      {:error, :unsupported_object_type} = err ->
        err

      {:error, _address} = err ->
        if Segmentation.fallback_error?(err) do
          read_properties_for_scan(address, object, opts)
        else
          err
        end
    end
  end

  # Fallback that reads a curated set of properties individually (no RPM).
  # This allows scanning devices that do not support segmentation.
  # The resulting plain map is sufficient for summarize_object/1 and hierarchy
  # building (for Structured View subordinate lists etc.).
  defp read_properties_for_scan(address, %ObjectIdentifier{} = object_id, opts) do
    props = [
      :object_name,
      :present_value,
      :description,
      :units,
      :status_flags,
      :event_state,
      :event_timestamps,
      :priority_array,
      :number_of_states,
      :state_text,
      :resolution,
      :out_of_service,
      :subordinate_list,
      :subordinate_annotations,
      :node_type,
      :node_subtype,
      :object_identifier
    ]

    read_opts = Keyword.take(opts, [:allow_unknown_properties, :remote_device_id])

    props
    |> Task.async_stream(
      fn prop ->
        case Client.read_property(address, object_id, prop, read_opts) do
          {:ok, value} -> {prop, value}
          _address -> nil
        end
      end,
      max_concurrency: 6,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce(%{}, fn
      {:ok, {prop, value}}, acc -> Map.put(acc, prop, value)
      _address, acc -> acc
    end)
    |> then(&{:ok, &1})
  end

  defp bump_scan_progress(
         device_id,
         done_counter,
         error_counter,
         skip_counter,
         total,
         current,
         error_log
       ) do
    :counters.add(done_counter, 1, 1)
    done = :counters.get(done_counter, 1)

    if done == 1 or done == total or rem(done, report_interval(total)) == 0 do
      report_progress(device_id, %{
        stage: :scanning_objects,
        done: done,
        total: total,
        errors: :counters.get(error_counter, 1),
        skipped: :counters.get(skip_counter, 1),
        detail: format_current_object(current),
        error_log: Enum.reverse(error_log)
      })
    end
  end

  defp prepend_scan_error(error_log, object_id, reason) do
    [
      %{
        object: format_current_object(object_id),
        message: ErrorMessage.format_reason(reason)
      }
      | error_log
    ]
  end

  defp bump_object_list_progress(device_id, counter, total) do
    :counters.add(counter, 1, 1)
    done = :counters.get(counter, 1)

    if done == 1 or done == total or rem(done, report_interval(total)) == 0 do
      report_progress(device_id, %{
        stage: :reading_object_list,
        done: done,
        total: total
      })
    end
  end

  defp report_interval(total) when total <= 50, do: 1
  defp report_interval(total), do: max(1, div(total, 50))

  defp normalize_object_ids(%BACnetArray{} = array),
    do: normalize_object_ids(BACnetArray.to_list(array))

  defp normalize_object_ids(list) when is_list(list) do
    list
    |> Enum.map(fn
      %Encoding{value: val} -> val
      %ObjectIdentifier{} = oid -> oid
      other -> other
    end)
    |> Enum.filter(&match?(%ObjectIdentifier{}, &1))
  end

  defp normalize_object_ids(_array), do: []

  defp format_current_object({%ObjectIdentifier{type: type, instance: instance}, _obj}),
    do: "#{type}:#{instance}"

  defp format_current_object(%ObjectIdentifier{type: type, instance: instance}),
    do: "#{type}:#{instance}"

  defp format_current_object(_format_current_object), do: nil

  defp normalize_error_log(error_log) when is_list(error_log) do
    Enum.map(error_log, fn
      %{object: object, message: message} when is_binary(message) ->
        %{object: object, message: message}

      %{object: object, message: message} ->
        %{object: object, message: to_string(message)}

      {object, message} ->
        %{object: object, message: to_string(message)}

      message when is_binary(message) ->
        %{object: nil, message: message}

      other ->
        %{object: nil, message: inspect(other)}
    end)
  end

  defp normalize_error_log(_error_log), do: []

  defp report_progress(device_id, progress) when is_map(progress) do
    normalized =
      %{
        stage: Map.get(progress, :stage, :connecting),
        done: Map.get(progress, :done, 0),
        total: Map.get(progress, :total),
        errors: Map.get(progress, :errors, 0),
        skipped: Map.get(progress, :skipped, 0),
        detail: Map.get(progress, :detail),
        error_log: normalize_error_log(Map.get(progress, :error_log, []))
      }

    Phoenix.PubSub.broadcast(
      BacView.PubSub,
      "device:#{device_id}:load_progress",
      {:device_load_progress, normalized}
    )
  end

  defp summarize_object({%ObjectIdentifier{type: type, instance: instance} = object_id, obj}) do
    name = object_name(obj)
    present_value = Map.get(obj, :present_value)
    units = Map.get(obj, :units)

    object_context =
      Map.merge(
        %{type: type, units: units, resolution: Map.get(obj, :resolution)},
        MultistateState.object_fields(obj)
      )

    %{
      object_id: object_id,
      type: type,
      instance: instance,
      type_label: ObjectTypes.short_label(type),
      name: name,
      description: object_description(obj) || nil,
      status_flags: extract_status_flags(obj),
      event_state: Map.get(obj, :event_state),
      event_timestamps: extract_event_timestamps(obj),
      present_value: present_value,
      present_value_formatted:
        PropertyFormatter.format_present_value(present_value, object_context),
      units: units,
      writable: writable?(obj),
      commandable: commandable?(obj),
      updated_at: DateTime.utc_now()
    }
    |> Map.merge(object_context)
    |> Map.merge(PropertyWriter.active_priority_info(obj, units, object_context))
    |> maybe_put_log_property_refs(type, obj)
  end

  defp object_name(obj) when is_map(obj) do
    Map.get(obj, :object_name) || Map.get(obj, :name)
  end

  defp object_name(_obj), do: nil

  defp object_description(obj) when is_map(obj) do
    case Map.get(obj, :description) do
      desc when is_binary(desc) and desc != "" -> desc
      _obj -> nil
    end
  end

  defp extract_status_flags(obj) when is_map(obj) do
    case Map.get(obj, :status_flags) do
      %StatusFlags{} = flags -> flags
      _obj -> nil
    end
  end

  defp extract_event_timestamps(obj) when is_map(obj) do
    case Map.get(obj, :event_timestamps) do
      %EventTimestamps{} = timestamps -> timestamps
      _obj -> nil
    end
  end

  @doc false
  @spec refresh_object_from_properties(map(), [map()]) :: map()
  def refresh_object_from_properties(%{} = object, props) when is_list(props) do
    apply_properties_to_object(object, props)
  end

  defp sync_object_fields_from_properties(
         objects,
         %ObjectIdentifier{type: type, instance: instance},
         props
       )
       when is_list(objects) and is_list(props) do
    Enum.map(objects, fn obj ->
      if obj.type == type and obj.instance == instance do
        apply_properties_to_object(obj, props)
      else
        obj
      end
    end)
  end

  defp sync_object_fields_from_properties(objects, _object, _props), do: objects

  defp apply_properties_to_object(obj, props) do
    now = DateTime.utc_now()
    present_prop = Enum.find(props, &(&1.property == :present_value))

    obj
    |> maybe_put_field(:name, object_name_from_properties(props))
    |> maybe_put_field(:description, description_from_properties(props))
    |> maybe_put_field(:units, property_row_value(props, :units))
    |> maybe_put_field(:resolution, property_row_value(props, :resolution))
    |> maybe_put_field(:out_of_service, property_row_value(props, :out_of_service))
    |> maybe_put_present_value(present_prop)
    |> maybe_put_multistate_fields(props)
    |> maybe_put_status_flags(props)
    |> maybe_put_field(:event_state, property_row_value(props, :event_state))
    |> maybe_put_field(:event_timestamps, extract_event_timestamps_from_properties(props))
    |> maybe_put_priority_array(props)
    |> maybe_put_log_property_refs_from_properties(props)
    |> Map.put(:updated_at, now)
    |> then(fn updated ->
      Map.merge(updated, %{
        writable: writable?(updated),
        commandable: commandable?(updated)
      })
    end)
  end

  defp object_name_from_properties(props) do
    case property_row_value(props, :object_name) do
      name when is_binary(name) and name != "" -> name
      _props -> nil
    end
  end

  defp description_from_properties(props) do
    case property_row_value(props, :description) do
      desc when is_binary(desc) and desc != "" -> desc
      _props -> nil
    end
  end

  defp maybe_put_present_value(obj, %{value: value} = prop) do
    coerced = PropertyFormatter.coerce_present_value(value, obj, prop)

    MapHelpers.update(obj, %{
      present_value: coerced,
      present_value_formatted: PropertyFormatter.format_present_value(value, obj, prop)
    })
  end

  defp maybe_put_present_value(obj, _prop), do: obj

  defp maybe_put_multistate_fields(obj, props) do
    obj
    |> maybe_put_field(:number_of_states, property_row_value(props, :number_of_states))
    |> maybe_put_field(
      :state_text,
      MultistateState.normalize_state_text(property_row_value(props, :state_text))
    )
  end

  defp maybe_put_status_flags(obj, props) do
    case property_row_value(props, :status_flags) do
      nil ->
        obj

      flags ->
        case StatusFlagsParser.normalize(flags) do
          nil -> obj
          normalized -> MapHelpers.update(obj, %{status_flags: normalized})
        end
    end
  end

  defp maybe_put_priority_array(obj, props) do
    case property_row_value(props, :priority_array) do
      nil ->
        obj

      priority_array ->
        obj_with_pa = Map.put(obj, :priority_array, priority_array)

        MapHelpers.update(obj_with_pa, PropertyWriter.active_priority_info(obj_with_pa))
    end
  end

  defp extract_event_timestamps_from_properties(props) do
    case property_row_value(props, :event_timestamps) do
      %EventTimestamps{} = timestamps -> timestamps
      _props -> nil
    end
  end

  defp property_row_value(props, property) do
    props
    |> Enum.find(fn row -> row.property == property end)
    |> case do
      %{value: value} -> value
      _props -> nil
    end
  end

  defp maybe_put_field(obj, _key, nil), do: obj
  defp maybe_put_field(obj, key, value), do: Map.put(obj, key, value)

  defp maybe_put_log_property_refs(obj, type, raw_obj)
       when type in [:trend_log, :trend_log_multiple] do
    Map.put(
      obj,
      :log_property_refs,
      TrendLogNavigation.log_property_refs_from_value(
        Map.get(raw_obj, :log_device_object_property)
      )
    )
  end

  defp maybe_put_log_property_refs(obj, _type, _raw_obj), do: obj

  defp maybe_put_log_property_refs_from_properties(
         %{type: type} = obj,
         props
       )
       when type in [:trend_log, :trend_log_multiple] and is_list(props) do
    refs =
      Enum.find_value(props, fn
        %{property: :log_device_object_property, value: value} ->
          TrendLogNavigation.log_property_refs_from_value(value)

        _prop ->
          nil
      end) || []

    Map.put(obj, :log_property_refs, refs)
  end

  defp maybe_put_log_property_refs_from_properties(obj, _props), do: obj

  defp apply_property_update(state, object_id, property, value, formatted) do
    now = DateTime.utc_now()

    objects =
      Enum.map(state.objects, fn obj ->
        if obj.type == object_id.type and obj.instance == object_id.instance do
          apply_object_property(obj, property, value, formatted, now)
        else
          obj
        end
      end)

    key = property_key(state.device_id, object_id)

    case :ets.lookup(@properties_table, key) do
      [{^key, props}] ->
        obj = find_cached_object(objects, object_id)

        updated =
          Enum.map(props, fn prop ->
            if prop.property == property do
              refresh_cached_property(prop, property, value, formatted, obj, now)
            else
              prop
            end
          end)

        :ets.insert(@properties_table, {key, updated})

      [] ->
        :ok
    end

    state = %{state | objects: objects}
    sync_objects_cache(state)
  end

  defp sync_objects_cache(%{device_id: device_id, objects: objects} = state) do
    :ets.insert(@objects_table, {device_id, objects})

    case state.device do
      %{} = device ->
        %{
          state
          | device:
              device
              |> Map.put(:objects, objects)
              |> Map.put(:object_count, length(objects))
        }

      _state ->
        state
    end
  end

  @doc false
  @spec loaded_snapshot(map()) :: map()
  def loaded_snapshot(%{device: device, objects: objects, hierarchy: hierarchy}) do
    device
    |> Map.put(:objects, objects)
    |> Map.put(:hierarchy, hierarchy)
    |> Map.put(:object_count, length(objects))
  end

  defp apply_object_property(obj, :present_value, value, _formatted, now) do
    coerced = PropertyFormatter.coerce_present_value(value, obj)

    MapHelpers.update(obj, %{
      present_value: coerced,
      present_value_formatted: PropertyFormatter.format_present_value(coerced, obj),
      updated_at: now
    })
  end

  defp apply_object_property(obj, :status_flags, value, _formatted, now) do
    case StatusFlagsParser.normalize(value) do
      nil ->
        obj

      flags ->
        MapHelpers.update(obj, %{
          status_flags: flags,
          updated_at: now
        })
    end
  end

  defp apply_object_property(obj, _property, _value, _formatted, _now), do: obj

  defp refresh_cached_property(prop, :present_value, value, _formatted, obj, now) do
    coerced = PropertyFormatter.coerce_present_value(value, obj, prop)

    display =
      coerced
      |> PropertyDisplay.build()
      |> put_present_value_display_formatted(coerced, obj, prop)

    formatted = Map.get(display, :formatted)

    MapHelpers.update(prop, %{
      value: coerced,
      value_display: display,
      value_formatted: formatted,
      updated_at: now
    })
  end

  defp refresh_cached_property(prop, :status_flags, value, _formatted, _obj, now) do
    case StatusFlagsParser.normalize(value) do
      nil ->
        prop

      flags ->
        display = PropertyDisplay.build(flags)

        MapHelpers.update(prop, %{
          value: flags,
          value_display: display,
          value_formatted: display.formatted,
          updated_at: now
        })
    end
  end

  defp refresh_cached_property(prop, _property, value, formatted, _obj, now) do
    MapHelpers.update(prop, %{
      value: value,
      value_formatted: formatted,
      updated_at: now
    })
  end

  defp put_present_value_display_formatted(display, value, obj, prop) do
    formatted = PropertyFormatter.format_present_value(value, obj, prop)
    Map.put(display, :formatted, formatted)
  end

  defp format_published_property(:present_value, value, obj) do
    PropertyFormatter.format_present_value(value, obj)
  end

  defp format_published_property(_property, value, _obj) do
    PropertyFormatter.format_value(value, nil)
  end

  defp find_cached_object(objects, %ObjectIdentifier{type: type, instance: instance}) do
    Enum.find(objects, &(&1.type == type and &1.instance == instance))
  end

  defp broadcast_property_update(device_id, object_id, property, value, formatted) do
    Phoenix.PubSub.broadcast(
      BacView.PubSub,
      "device:#{device_id}:cov",
      {:cov_update,
       %{
         device_id: device_id,
         type: object_id.type,
         instance: object_id.instance,
         property: property,
         value: value,
         formatted: formatted,
         at: DateTime.utc_now()
       }}
    )

    Phoenix.PubSub.broadcast(BacView.PubSub, "cov:updates", :cov_updated)
  end

  defp writable?(obj) when is_map(obj) do
    (Map.has_key?(obj, :present_value) and Map.has_key?(obj, :priority_array)) or
      (Map.has_key?(obj, :present_value) and not Map.has_key?(obj, :out_of_service))
  end

  defp commandable?(obj) when is_map(obj), do: PropertyWriter.has_priority_array?(obj)

  defp update_device_meta(device_id, loaded) do
    case :ets.lookup(@devices_table, device_id) do
      [{^device_id, device}] ->
        :ets.insert(@devices_table, {
          device_id,
          Map.merge(device, %{
            name: loaded.name,
            object_count: loaded.object_count,
            status: :loaded,
            loaded_at: loaded.loaded_at
          })
        })

      [] ->
        :ok
    end

    Phoenix.PubSub.broadcast(
      BacView.PubSub,
      "devices",
      {:devices_updated, Discovery.list_devices()}
    )
  end

  defp property_key(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    {device_id, type, instance}
  end
end
