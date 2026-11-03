defmodule BacView.BACnet.Protocol.CovNotificationExport do
  @moduledoc """
  CSV and JSON export of received COV notifications for a set of subscriptions.

  CSV follows the chart export, with one timestamp column and one value column
  per subscription. The value title is the chart series label: description,
  object type, instance, property, and the unit symbol when the chart would
  show one. A priority array lists all 16 slots. JSON keeps one record per
  notification, with structured values.
  """

  alias BACnet.Protocol.PriorityArray
  alias BacView.BACnet.PropertyExport
  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.Timezone

  @csv_separator ";"

  @spec select([map()], MapSet.t()) :: [map()]
  def select(notifications, %MapSet{} = keys) when is_list(notifications) do
    notifications
    |> Enum.filter(&selected?(&1, keys))
    |> Enum.sort_by(&sort_key/1)
  end

  @spec to_csv([map()], keyword()) :: String.t()
  def to_csv(rows, opts \\ []) when is_list(rows) do
    series = build_series(rows, opts)
    header = Enum.join(header_cells(series), @csv_separator) <> "\n"
    header <> csv_body(series)
  end

  @spec to_json([map()], keyword()) :: String.t()
  def to_json(rows, opts \\ []) when is_list(rows) do
    names = object_names(Keyword.get(opts, :objects, []))

    payload = %{
      device_id: Keyword.get(opts, :device_id),
      notifications: Enum.map(rows, &json_row(&1, names))
    }

    Jason.encode!(payload, pretty: true)
  end

  @spec filename(integer(), MapSet.t(), String.t()) :: String.t()
  def filename(device_id, %MapSet{} = keys, ext) when is_binary(ext) do
    case MapSet.to_list(keys) do
      [{type, instance, property}] ->
        "bacview-cov-#{filename_token(type)}-#{instance}-#{filename_token(property)}.#{ext}"

      _keys ->
        "bacview-cov-#{device_id}-notifications.#{ext}"
    end
  end

  defp selected?(entry, keys) do
    case subscription_key(entry) do
      {type, instance, property} -> key_selected?(keys, type, instance, property)
      nil -> false
    end
  end

  defp subscription_key(%{object_id: %{type: type, instance: instance}, property: property})
       when is_integer(instance) do
    {type, instance, property}
  end

  defp subscription_key(_entry), do: nil

  defp key_selected?(keys, type, instance, property) do
    candidates = [property | property_aliases(property)]

    Enum.any?(candidates, fn candidate ->
      MapSet.member?(keys, {type, instance, candidate})
    end)
  end

  defp property_aliases(property) when is_integer(property), do: [Integer.to_string(property)]
  defp property_aliases(property) when is_atom(property), do: [Atom.to_string(property)]

  defp property_aliases(property) when is_binary(property) do
    case Integer.parse(property) do
      {int, ""} -> [int]
      _parsed -> []
    end
  end

  defp property_aliases(_property), do: []

  defp sort_key(entry) do
    log_id = Map.get(entry, :log_id) || 0

    case Map.get(entry, :received_at) do
      %DateTime{} = received_at -> {0, DateTime.to_unix(received_at, :microsecond), log_id}
      _received_at -> {1, 0, log_id}
    end
  end

  defp build_series(rows, opts) do
    objects = object_by_key(Keyword.get(opts, :objects, []))

    rows
    |> Enum.group_by(&subscription_key/1)
    |> Enum.reject(fn {key, _entries} -> is_nil(key) end)
    |> Enum.sort_by(fn {{type, instance, property}, _entries} ->
      {to_string(type), instance, to_string(property)}
    end)
    |> Enum.map(fn {{type, instance, property}, entries} ->
      object = Map.get(objects, {type, instance})

      points =
        entries
        |> Enum.sort_by(&sort_key/1)
        |> Enum.map(fn entry ->
          %{
            timestamp: format_chart_timestamp(Map.get(entry, :received_at)),
            value: point_value(entry)
          }
        end)

      %{title: series_title(type, instance, property, object), points: points}
    end)
  end

  defp header_cells(series) do
    Enum.flat_map(series, fn serie ->
      ["timestamp", csv_cell(serie.title)]
    end)
  end

  defp csv_body(series) do
    case series_width(series) do
      0 ->
        ""

      width ->
        lines =
          Enum.map(0..(width - 1), fn index ->
            cells =
              Enum.flat_map(series, fn serie ->
                case Enum.at(serie.points, index) do
                  nil -> ["", ""]
                  point -> [point.timestamp, csv_cell(point.value)]
                end
              end)

            Enum.join(cells, @csv_separator)
          end)

        Enum.join(lines, "\n") <> "\n"
    end
  end

  defp series_width([]), do: 0

  defp series_width(series) do
    lengths = Enum.map(series, fn serie -> length(serie.points) end)
    Enum.max(lengths)
  end

  defp series_title(type, instance, property, object) do
    prop = property |> to_string() |> String.replace("_", " ")
    base = "#{type}:#{instance} #{prop}"

    label =
      case object_description(object) do
        nil -> base
        description -> "#{description} (#{base})"
      end

    case unit_label(property, object) do
      "" -> label
      unit -> "#{label} (#{unit})"
    end
  end

  defp unit_label(:present_value, %{units: unit}) do
    EngineeringUnits.symbol(unit)
  end

  defp unit_label(_property, _object), do: ""

  defp object_description(%{description: description}) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_description(_object), do: nil

  defp point_value(%{value: %PriorityArray{} = array}), do: priority_array_text(array)
  defp point_value(%{value: value}) when is_number(value) or is_boolean(value), do: value

  defp point_value(%{value: _value, formatted: formatted})
       when is_binary(formatted) and formatted != "" do
    formatted
  end

  defp point_value(%{value: value}), do: PropertyExport.value_text(value)

  defp format_chart_timestamp(%DateTime{} = received_at) do
    received_at
    |> DateTime.to_unix(:millisecond)
    |> Timezone.unix_ms_to_naive()
    |> NaiveDateTime.to_string()
  end

  defp format_chart_timestamp(_received_at), do: ""

  defp json_row(entry, names) do
    %{type: type, instance: instance} = entry.object_id

    %{
      received_at: format_received(Map.get(entry, :received_at)),
      object_type: property_token(type),
      object_instance: instance,
      object_name: Map.get(names, {type, instance}),
      property: property_token(Map.get(entry, :property)),
      value: json_term(Map.get(entry, :value)),
      value_text: value_text(entry),
      confirmed: Map.get(entry, :confirmed),
      time_remaining: Map.get(entry, :time_remaining)
    }
  end

  defp value_text(%{value: %PriorityArray{} = array}), do: priority_array_text(array)

  defp value_text(%{value: value, formatted: formatted})
       when is_binary(formatted) and formatted != "" and
              (is_number(value) or is_boolean(value) or is_binary(value) or is_atom(value)) do
    formatted
  end

  defp value_text(%{value: value}), do: PropertyExport.value_text(value)

  defp priority_array_text(%PriorityArray{} = array) do
    slots =
      array
      |> PriorityArray.to_list()
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn
        {nil, index} -> "#{index}: NULL"
        {slot, index} -> "#{index}: #{PropertyExport.value_text(slot)}"
      end)

    "[#{slots}]"
  end

  defp json_term(%PriorityArray{} = array) do
    array
    |> PriorityArray.to_list()
    |> Enum.with_index(1)
    |> Enum.map(fn {slot, priority} ->
      %{"priority" => priority, "value" => PropertyExport.json_term(slot)}
    end)
  end

  defp json_term(value), do: PropertyExport.json_term(value)

  defp object_by_key(objects) when is_list(objects) do
    Map.new(objects, fn object ->
      {{object.type, object.instance}, object}
    end)
  end

  defp object_by_key(_objects), do: %{}

  defp object_names(objects) when is_list(objects) do
    Map.new(objects, fn object ->
      {{object.type, object.instance}, object_name(object)}
    end)
  end

  defp object_names(_objects), do: %{}

  defp object_name(%{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_name(_object), do: nil

  defp format_received(%DateTime{} = received_at) do
    Timezone.format(received_at, "%Y-%m-%d %H:%M:%S")
  end

  defp format_received(_received_at), do: nil

  defp property_token(property) when is_atom(property), do: Atom.to_string(property)
  defp property_token(property) when is_integer(property), do: Integer.to_string(property)
  defp property_token(property) when is_binary(property), do: property
  defp property_token(property), do: to_string(property)

  defp filename_token(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_-]/, "-")
  end

  defp csv_cell(nil), do: ""
  defp csv_cell(true), do: "true"
  defp csv_cell(false), do: "false"
  defp csv_cell(value) when is_integer(value), do: Integer.to_string(value)

  defp csv_cell(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 6)
  end

  defp csv_cell(value) when is_atom(value), do: csv_cell(Atom.to_string(value))

  defp csv_cell(value) when is_binary(value) do
    "\"#{String.replace(value, "\"", "\"\"")}\""
  end

  defp csv_cell(value), do: csv_cell(to_string(value))
end
