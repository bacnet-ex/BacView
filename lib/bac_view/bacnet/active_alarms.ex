defmodule BacView.BACnet.ActiveAlarms do
  @moduledoc """
  Builds active-alarm popup entries from cached device/object data.
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.AlarmEvent
  alias BacView.BACnet.Protocol.EventTimestamp

  @objects_table :bacview_objects
  @properties_table :bacview_properties
  @devices_table :bacview_devices

  @type entry :: %{
          id: String.t(),
          device_id: non_neg_integer(),
          device_label: String.t() | nil,
          object_label: String.t(),
          description: String.t() | nil,
          alarm_since_label: String.t(),
          sort_key: integer(),
          device_path: String.t() | nil,
          object_path: String.t()
        }

  @type device_group :: %{
          device_id: non_neg_integer(),
          device_label: String.t(),
          device_description: String.t() | nil,
          count: non_neg_integer(),
          sort_key: integer(),
          device_path: String.t()
        }

  @spec object_alarm_since(map()) :: %{
          at: DateTime.t() | nil,
          label: String.t(),
          sort_key: integer()
        }
  def object_alarm_since(obj) when is_map(obj) do
    event_state = object_event_state(obj)
    event_timestamps = Map.get(obj, :event_timestamps)
    since = EventTimestamp.alarm_since(event_timestamps, event_state)
    sort_key = fallback_sort_key(since.sort_key, %{updated_at: Map.get(obj, :updated_at)})

    %{since | sort_key: sort_key}
  end

  @spec device_groups([integer()]) :: [device_group()]
  def device_groups(device_ids) when is_list(device_ids) do
    device_ids
    |> Enum.map(fn device_id ->
      entries = list(device_id: device_id)
      build_device_group(device_id, entries)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.sort_key, :desc)
  end

  @spec list(keyword()) :: [entry()]
  def list(opts \\ []) do
    device_id = Keyword.get(opts, :device_id)
    objects_override = Keyword.get(opts, :objects)

    device_id
    |> collect_events(objects_override)
    |> Enum.map(&build_entry(&1, objects_override))
    |> sort_entries()
  end

  @spec count(keyword()) :: non_neg_integer()
  def count(opts \\ []), do: opts |> list() |> length()

  defp collect_events(nil, _objects_override) do
    AlarmEvent.list_all_active_events()
  end

  defp collect_events(device_id, objects_override) do
    active_events = AlarmEvent.list_active_events(device_id)

    active_keys =
      MapSet.new(active_events, fn event ->
        {event.object_id.type, event.object_id.instance}
      end)

    status_events =
      device_id
      |> cached_objects(objects_override)
      |> Enum.filter(&status_flag_alarm?/1)
      |> Enum.reject(fn obj -> MapSet.member?(active_keys, {obj.type, obj.instance}) end)
      |> Enum.map(&synthetic_event(device_id, &1))

    active_events ++ status_events
  end

  defp build_entry(event, objects_override) do
    device_id = event.device_id
    object_id = event.object_id
    cached = lookup_cached_object(device_id, object_id, objects_override)

    description =
      cached_description(cached) ||
        Map.get(event, :description) ||
        string_value(Map.get(event, :message_text))

    event_timestamps =
      cached_event_timestamps(cached) ||
        cached_property_value(device_id, object_id, :event_timestamps)

    since = EventTimestamp.alarm_since(event_timestamps, event.event_state)
    sort_key = fallback_sort_key(since.sort_key, event)

    build_entry_map(device_id, object_id, cached, event, description, since, sort_key)
  end

  defp build_device_group(_device_id, []), do: nil

  defp build_device_group(device_id, entries) do
    device = device_info(device_id)
    sort_key = entries |> Enum.map(& &1.sort_key) |> Enum.max()

    %{
      device_id: device_id,
      device_label: device_label(device) || Integer.to_string(device_id),
      device_description: device_description(device),
      count: length(entries),
      sort_key: sort_key,
      device_path: device_path(device_id)
    }
  end

  defp build_entry_map(device_id, object_id, _cached, _event, description, since, sort_key) do
    device = device_info(device_id)

    %{
      id: "#{device_id}-#{object_id.type}-#{object_id.instance}",
      device_id: device_id,
      device_label: device_label(device),
      object_label: "#{object_id.type}:#{object_id.instance}",
      description: description,
      alarm_since_label: since.label,
      sort_key: sort_key,
      device_path: device_path(device_id),
      object_path: object_path(device_id, object_id)
    }
  end

  defp sort_entries(entries) do
    Enum.sort_by(entries, & &1.sort_key, :desc)
  end

  defp fallback_sort_key(0, %{updated_at: %DateTime{} = updated_at}),
    do: DateTime.to_unix(updated_at, :microsecond)

  defp fallback_sort_key(sort_key, _event), do: sort_key

  defp cached_objects(_device_id, objects_override) when is_list(objects_override),
    do: objects_override

  defp cached_objects(device_id, _objects_override) do
    if :ets.whereis(@objects_table) == :undefined do
      []
    else
      case :ets.lookup(@objects_table, device_id) do
        [{^device_id, objects}] when is_list(objects) -> objects
        _device_id -> []
      end
    end
  end

  defp lookup_cached_object(
         device_id,
         %ObjectIdentifier{type: type, instance: instance},
         override
       ) do
    device_id
    |> cached_objects(override)
    |> Enum.find(fn obj -> obj.type == type and obj.instance == instance end)
  end

  defp cached_properties(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    key = {device_id, type, instance}

    if :ets.whereis(@properties_table) == :undefined do
      []
    else
      case :ets.lookup(@properties_table, key) do
        [{^key, props}] when is_list(props) -> props
        _device_id -> []
      end
    end
  end

  defp cached_property_value(device_id, object_id, property) do
    device_id
    |> cached_properties(object_id)
    |> Enum.find(fn row -> row.property == property end)
    |> case do
      %{value: value} -> value
      _device_id -> nil
    end
  end

  defp cached_description(%{description: description}), do: string_value(description)
  defp cached_description(_cached_description), do: nil

  defp cached_event_timestamps(%{event_timestamps: event_timestamps}), do: event_timestamps
  defp cached_event_timestamps(_cached), do: nil

  defp status_flag_alarm?(%{status_flags: %StatusFlags{in_alarm: true}}), do: true
  defp status_flag_alarm?(%{status_flags: %StatusFlags{fault: true}}), do: true
  defp status_flag_alarm?(_status_flag_alarm), do: false

  defp object_event_state(obj) do
    Map.get(obj, :event_state) ||
      if(fault_state?(obj), do: :fault, else: :offnormal)
  end

  defp synthetic_event(device_id, obj) do
    %{
      device_id: device_id,
      object_id: %ObjectIdentifier{type: obj.type, instance: obj.instance},
      event_state: object_event_state(obj),
      description: cached_description(obj),
      updated_at: Map.get(obj, :updated_at)
    }
  end

  defp fault_state?(%{status_flags: %StatusFlags{fault: true}}), do: true
  defp fault_state?(_fault_state), do: false

  defp device_info(device_id) do
    if :ets.whereis(@devices_table) == :undefined do
      nil
    else
      case :ets.lookup(@devices_table, device_id) do
        [{^device_id, device}] -> device
        _device_id -> nil
      end
    end
  end

  defp device_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp device_label(%{instance: instance}), do: "Device #{instance}"
  defp device_label(_name), do: nil

  defp device_description(%{description: description}), do: string_value(description)
  defp device_description(_device), do: nil

  defp device_path(device_id), do: "/devices/#{device_id}"

  defp object_path(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    "/devices/#{device_id}/objects/#{type}/#{instance}"
  end

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_value(_value), do: nil
end
