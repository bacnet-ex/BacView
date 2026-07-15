defmodule BacView.BACnet.EventExport do
  @moduledoc """
  Enriches polled alarm events with object properties read from the device
  and formats CSV/JSON exports.
  """

  alias BACnet.Protocol.EventMessageTexts
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.BACnet.Discovery

  @read_opts [allow_unknown_properties: :no_unpack, ignore_unsupported_object_types: true]
  @csv_separator ";"

  @spec export(integer(), :json | :csv) :: {:ok, String.t()} | {:error, term()}
  def export(device_id, format) do
    events = BacView.BACnet.AlarmEvent.list_polled_events(device_id)

    with {:ok, enriched} <- enrich_events(device_id, events) do
      {:ok, format_export(enriched, format)}
    end
  end

  @spec enrich_events(integer(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def enrich_events(device_id, events) when is_list(events) do
    with {:ok, %{address: address}} <- fetch_device(device_id) do
      object_ids = events |> Enum.map(& &1.object_id) |> Enum.uniq_by(&object_key/1)

      object_details =
        object_ids
        |> Task.async_stream(
          fn object_id ->
            {object_key(object_id), read_object_details(address, object_id, device_id)}
          end,
          timeout: :infinity,
          ordered: true
        )
        |> Enum.into(%{}, fn {:ok, {key, details}} -> {key, details} end)

      enriched =
        Enum.map(events, fn event ->
          details = Map.get(object_details, object_key(event.object_id), %{})
          enrich_event(event, details)
        end)

      {:ok, enriched}
    end
  end

  @doc false
  @spec enrich_event(map(), map()) :: map()
  def enrich_event(event, object_details) do
    message =
      event.message_text ||
        message_for_state(event.event_state, object_details[:event_message_texts])

    event
    |> Map.put(:description, object_details[:description])
    |> Map.put(:object_name, object_details[:object_name])
    |> Map.put(:notify_type, object_details[:notify_type] || event.notify_type)
    |> Map.put(
      :notification_class,
      object_details[:notification_class] || event.notification_class
    )
    |> Map.put(:message_text, message)
  end

  @doc false
  @spec format_export([map()], :json | :csv) :: String.t()
  def format_export(events, :json), do: export_json(events)
  def format_export(events, :csv), do: export_csv(events)

  defp fetch_device(device_id) do
    case safe_get_device(device_id) do
      {:ok, device} -> {:ok, device}
      :error -> {:error, :device_not_found}
    end
  end

  defp safe_get_device(device_id) do
    case Discovery.get_device(device_id) do
      {:ok, device} -> {:ok, device}
      :error -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp read_object_details(address, %ObjectIdentifier{} = object_id, device_id) do
    case Client.read_object(address, object_id, Keyword.put(@read_opts, :device_id, device_id)) do
      {:ok, obj} when is_map(obj) -> extract_object_details(obj)
      _address -> %{}
    end
  end

  defp extract_object_details(obj) do
    %{
      description: string_value(Map.get(obj, :description)),
      object_name: string_value(Map.get(obj, :object_name)),
      notify_type: Map.get(obj, :notify_type),
      notification_class: Map.get(obj, :notification_class),
      event_message_texts: Map.get(obj, :event_message_texts)
    }
  end

  defp object_key(%ObjectIdentifier{type: type, instance: instance}), do: {type, instance}

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_value(_value), do: nil

  defp message_for_state(_state, nil), do: nil

  defp message_for_state(state, %EventMessageTexts{} = texts) do
    text =
      case state do
        :offnormal -> texts.to_offnormal
        :high_limit -> texts.to_offnormal
        :low_limit -> texts.to_offnormal
        :life_safety_alarm -> texts.to_offnormal
        :fault -> texts.to_fault
        :normal -> texts.to_normal
        _state -> nil
      end

    string_value(text)
  end

  defp message_for_state(_state, _texts), do: nil

  defp export_json(events) do
    payload =
      Enum.map(events, fn event ->
        %{
          object: object_label(event),
          description: event.description,
          name: event.object_name,
          event_state: event.event_state,
          notify_type: event.notify_type,
          notification_class: event.notification_class,
          message: event.message_text,
          source: event.source,
          updated_at: DateTime.to_iso8601(event.updated_at)
        }
      end)

    Jason.encode!(payload, pretty: true)
  end

  defp export_csv(events) do
    header =
      [
        "object",
        "description",
        "name",
        "event_state",
        "notify_type",
        "notification_class",
        "message",
        "source",
        "updated_at"
      ]
      |> Enum.join(@csv_separator)
      |> Kernel.<>("\n")

    rows =
      Enum.map(events, fn event ->
        Enum.map_join(
          [
            object_label(event),
            event.description,
            event.object_name,
            event.event_state,
            event.notify_type,
            event.notification_class,
            event.message_text,
            event.source,
            DateTime.to_iso8601(event.updated_at)
          ],
          @csv_separator,
          &csv_cell/1
        )
      end)

    header <> Enum.join(rows, "\n")
  end

  defp object_label(%{object_id: %{type: type, instance: instance}}),
    do: "#{type}:#{instance}"

  defp csv_cell(nil), do: ""
  defp csv_cell(value) when is_binary(value), do: "\"#{String.replace(value, "\"", "\"\"")}\""
  defp csv_cell(value) when is_atom(value), do: Atom.to_string(value)
  defp csv_cell(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp csv_cell(value), do: to_string(value)
end
