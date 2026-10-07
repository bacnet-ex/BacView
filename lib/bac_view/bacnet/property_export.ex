defmodule BacView.BACnet.PropertyExport do
  @moduledoc """
  Builds a CSV or JSON export of selected properties for selected objects.

  Property columns are the union of properties known on the selected objects.
  An object that does not have a selected property contributes an empty CSV
  field or JSON `null`.

  Nested CSV values use brackets for lists and braces for structs, with the
  same field labels as the property display. A flat summary joins every entry
  with commas, so list items cannot be told apart. Scalars stay display text.

  A weekly schedule is one localized weekday per line. Times drop a zero
  fractional part. Entry values use the object's multistate text or binary
  active/inactive text when that object, or the object it references, has one.
  """

  use Gettext, backend: BacViewWeb.Gettext

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.DailySchedule
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PriorityArray
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Protocol.TimeValue

  alias BacView.BACnet.Protocol.BinaryPV
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.Text

  @type property_id :: atom() | non_neg_integer()
  @type export_file :: %{filename: String.t(), content: binary(), mime: String.t()}
  @type object_entry :: %{
          key: String.t(),
          device_id: non_neg_integer(),
          device_instance: non_neg_integer(),
          device_name: String.t() | nil,
          type: atom() | non_neg_integer(),
          instance: non_neg_integer(),
          name: String.t() | nil,
          type_label: String.t(),
          property_ids: [property_id()]
        }
  @type group :: %{
          device_id: non_neg_integer(),
          device_instance: non_neg_integer(),
          device_name: String.t() | nil,
          scanned: [{ObjectIdentifier.t(), term()}]
        }

  @csv_separator ";"
  @csv_mime "text/csv; charset=utf-8"
  @json_mime "application/json; charset=utf-8"
  @internal_keys [:__struct__, :_metadata, :_unknown_properties]
  @identity_columns ["device_instance", "object_type", "object_instance"]

  @doc """
  Summaries for the export dialog, one per scanned object.
  """
  @spec entries(map(), [term()]) :: [object_entry()]
  def entries(%{id: device_id, instance: device_instance} = device, scanned)
      when is_integer(device_id) and is_integer(device_instance) and is_list(scanned) do
    scanned
    |> Enum.flat_map(&entry(device, device_id, device_instance, &1))
    |> Enum.sort_by(&{&1.device_instance, String.downcase(&1.type_label), &1.instance})
  end

  def entries(_device, _scanned), do: []

  @doc """
  Objects whose type matches `filter`. An empty or unknown filter returns every object.
  """
  @spec filter_entries([object_entry()], term()) :: [object_entry()]
  def filter_entries(objects, filter) when is_list(objects) do
    case parse_identifier(filter) do
      {:ok, type} -> Enum.filter(objects, &(&1.type == type))
      :error -> objects
    end
  end

  @doc """
  Objects matching the type filter and search text.

  An empty search matches every object that passed the type filter. The search
  looks at the object name, type, instance, and device name.
  """
  @spec filter_objects([object_entry()], term(), term()) :: [object_entry()]
  def filter_objects(objects, type_filter, query) when is_list(objects) do
    objects
    |> filter_entries(type_filter)
    |> Enum.filter(&query_match?(object_search_text(&1), query))
  end

  @doc """
  Properties whose label or token contains the search text.

  An empty search returns every property.
  """
  @spec filter_properties([map()], term()) :: [map()]
  def filter_properties(properties, query) when is_list(properties) do
    Enum.filter(properties, &query_match?("#{&1.label} #{&1.token}", query))
  end

  defp object_search_text(object) do
    [
      object.name,
      object.type_label,
      property_token(object.type),
      object.instance,
      object.device_name,
      object.device_instance
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &to_string/1)
    |> String.downcase()
  end

  defp query_match?(_haystack, query) when query in [nil, ""], do: true

  defp query_match?(haystack, query) when is_binary(query) do
    needle = query |> String.trim() |> String.downcase()
    needle == "" or String.contains?(haystack, needle)
  end

  defp query_match?(_haystack, _query), do: true

  @doc """
  Property identifiers known on this object.

  Bacstack objects contribute `properties_list` plus `_unknown_properties`.
  Plain maps contribute their keys.
  """
  @spec property_ids(term()) :: [property_id()]
  def property_ids(obj) do
    ids = known_ids(obj) ++ unknown_ids(obj)

    ids
    |> Enum.filter(&(is_atom(&1) or (is_integer(&1) and &1 >= 0)))
    |> Enum.uniq()
  end

  @spec property_token(property_id() | atom() | integer()) :: String.t()
  def property_token(id) when is_atom(id), do: Atom.to_string(id)
  def property_token(id) when is_integer(id), do: Integer.to_string(id)

  @spec property_label(property_id()) :: String.t()
  def property_label(id) when is_atom(id) do
    id
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  def property_label(id) when is_integer(id) do
    case Constants.by_value(:property_identifier, id) do
      {:ok, name} -> property_label(name)
      :error -> "property #{id}"
    end
  end

  @spec object_key(integer(), atom() | integer(), integer()) :: String.t()
  def object_key(device_id, type, instance)
      when is_integer(device_id) and is_integer(instance) do
    "#{device_id}|#{property_token(type)}|#{instance}"
  end

  @spec parse_identifier(term()) :: {:ok, atom() | non_neg_integer()} | :error
  def parse_identifier(nil), do: :error
  def parse_identifier(id) when is_atom(id), do: {:ok, id}
  def parse_identifier(id) when is_integer(id) and id >= 0, do: {:ok, id}

  def parse_identifier(id) when is_binary(id) do
    trimmed = String.trim(id)

    if trimmed == "" do
      :error
    else
      case Integer.parse(trimmed) do
        {int, ""} when int >= 0 ->
          {:ok, int}

        _other ->
          try do
            {:ok, String.to_existing_atom(trimmed)}
          rescue
            ArgumentError -> :error
          end
      end
    end
  end

  def parse_identifier(_id), do: :error

  @spec parse_identifier_list(term()) :: [property_id()]
  def parse_identifier_list(nil), do: []

  def parse_identifier_list(values) when is_list(values) do
    values
    |> Enum.flat_map(fn value ->
      case parse_identifier(value) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  def parse_identifier_list(value), do: parse_identifier_list([value])

  @spec export([group()], [String.t()], [property_id()], :csv | :json) ::
          {:ok, export_file()} | {:error, term()}
  def export([], _keys, _property_ids, _format), do: {:error, :no_devices}
  def export(_groups, _keys, [], _format), do: {:error, :no_properties_selected}

  def export(groups, keys, property_ids, format)
      when is_list(groups) and is_list(keys) and is_list(property_ids) and format in [:csv, :json] do
    rows = collect_rows(groups, keys)
    columns = Enum.uniq(property_ids)

    if rows == [] do
      {:error, :no_objects}
    else
      {:ok,
       %{
         filename: filename(rows, format),
         content: render(rows, columns, format),
         mime: mime(format)
       }}
    end
  end

  def export(_groups, _keys, _property_ids, _format), do: {:error, :invalid_export_format}

  defp entry(
         device,
         device_id,
         device_instance,
         {%ObjectIdentifier{type: type, instance: instance}, obj}
       )
       when is_map(obj) and is_integer(instance) and instance >= 0 do
    [
      %{
        key: object_key(device_id, type, instance),
        device_id: device_id,
        device_instance: device_instance,
        device_name: device_name(device),
        type: type,
        instance: instance,
        name: object_name(obj),
        type_label: ObjectTypes.short_label(type),
        property_ids: property_ids(obj)
      }
    ]
  end

  defp entry(_device, _device_id, _device_instance, _pair), do: []

  defp device_name(%{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp device_name(_device), do: nil

  defp object_name(obj) do
    case Map.get(obj, :object_name) do
      name when is_binary(name) ->
        case String.trim(name) do
          "" -> nil
          trimmed -> Text.sanitize_utf8(trimmed)
        end

      _name ->
        nil
    end
  end

  defp known_ids(%{_metadata: %{properties_list: list}}) when is_list(list) do
    Enum.filter(list, &is_atom/1)
  end

  defp known_ids(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.reject(&internal_key?/1)
  end

  defp known_ids(map) when is_map(map) do
    map
    |> Map.keys()
    |> Enum.reject(&internal_key?/1)
  end

  defp known_ids(_obj), do: []

  defp unknown_ids(%{_unknown_properties: props}) when is_map(props), do: Map.keys(props)
  defp unknown_ids(_obj), do: []

  defp internal_key?(key), do: key in @internal_keys

  defp collect_rows(groups, keys) do
    wanted = MapSet.new(keys)

    groups
    |> Enum.flat_map(&rows_for_group(&1, wanted))
    |> Enum.sort_by(fn row ->
      {row.device_instance, property_token(row.object_type), row.object_instance}
    end)
  end

  defp rows_for_group(%{scanned: scanned} = group, wanted) when is_list(scanned) do
    objects = device_objects(scanned)
    Enum.flat_map(scanned, &row_for_pair(group, wanted, objects, &1))
  end

  defp rows_for_group(_group, _wanted), do: []

  defp row_for_pair(
         group,
         wanted,
         device_objects,
         {%ObjectIdentifier{type: type, instance: instance}, obj}
       )
       when is_map(obj) do
    key = object_key(group.device_id, type, instance)

    if MapSet.member?(wanted, key) do
      [
        %{
          device_instance: group.device_instance,
          object_type: type,
          object_instance: instance,
          object: obj,
          device_objects: device_objects
        }
      ]
    else
      []
    end
  end

  defp row_for_pair(_group, _wanted, _device_objects, _pair), do: []

  defp device_objects(scanned) do
    Enum.flat_map(scanned, fn
      {%ObjectIdentifier{type: type, instance: instance}, obj} when is_map(obj) ->
        [Map.merge(plain_object(obj), %{type: type, instance: instance})]

      _pair ->
        []
    end)
  end

  defp plain_object(obj) when is_struct(obj), do: Map.from_struct(obj)
  defp plain_object(obj) when is_map(obj), do: obj

  defp render(rows, columns, :csv), do: render_csv(rows, columns)
  defp render(rows, columns, :json), do: render_json(rows, columns)

  defp render_csv(rows, columns) do
    header =
      (@identity_columns ++ Enum.map(columns, &property_token/1))
      |> Enum.map_join(@csv_separator, &csv_cell/1)
      |> Kernel.<>("\n")

    body =
      Enum.map_join(rows, "\n", fn row ->
        identity = [
          Integer.to_string(row.device_instance),
          property_token(row.object_type),
          Integer.to_string(row.object_instance)
        ]

        values = Enum.map(columns, &csv_property(row, &1))

        Enum.map_join(identity ++ values, @csv_separator, &csv_cell/1)
      end)

    header <> body
  end

  defp render_json(rows, columns) do
    payload =
      Enum.map(rows, fn row ->
        %{
          "device_instance" => row.device_instance,
          "object_type" => property_token(row.object_type),
          "object_instance" => row.object_instance,
          "properties" => json_properties(row.object, columns)
        }
      end)

    Jason.encode!(payload, pretty: true)
  end

  defp json_properties(obj, columns) do
    Map.new(columns, fn id -> {property_token(id), json_property(obj, id)} end)
  end

  defp csv_property(row, property) do
    case fetch_property(row.object, property) do
      :error ->
        ""

      {:ok, nil} ->
        ""

      {:ok, value} ->
        if property == :weekly_schedule do
          format_weekly_schedule(value, schedule_label_object(row)) ||
            format_csv_value(value, nil)
        else
          format_csv_value(value, csv_units(row.object, property))
        end
    end
  end

  defp json_property(obj, property) do
    case fetch_property(obj, property) do
      :error -> nil
      {:ok, value} -> json_value(value)
    end
  end

  defp fetch_property(obj, property) do
    cond do
      known?(obj, property) -> {:ok, Map.get(obj, property)}
      unknown?(obj, property) -> {:ok, Map.fetch!(obj._unknown_properties, property)}
      true -> :error
    end
  end

  defp known?(%{_metadata: %{properties_list: list}}, property) when is_list(list) do
    is_atom(property) and property in list
  end

  defp known?(map, property) when is_map(map) do
    not internal_key?(property) and Map.has_key?(map, property)
  end

  defp known?(_obj, _property), do: false

  defp unknown?(%{_unknown_properties: props}, property) when is_map(props) do
    Map.has_key?(props, property)
  end

  defp unknown?(_obj, _property), do: false

  defp csv_units(obj, :present_value) when is_map(obj), do: Map.get(obj, :units)
  defp csv_units(_obj, _property), do: nil

  defp format_csv_value(value, units), do: csv_value(value, units)

  defp format_weekly_schedule(%BACnetArray{} = array, object) do
    format_weekly_days(BACnetArray.to_list(array), object)
  end

  defp format_weekly_schedule(days, object) when is_list(days) do
    if Enum.any?(days, &daily_schedule?/1), do: format_weekly_days(days, object)
  end

  defp format_weekly_schedule(_value, _object), do: nil

  defp format_weekly_days(days, object) do
    days
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {day, index} ->
      "#{weekday_name(index)}: #{format_day_entries(day, object)}"
    end)
  end

  defp daily_schedule?(%DailySchedule{}), do: true
  defp daily_schedule?(_day), do: false

  defp format_day_entries(%DailySchedule{schedule: entries}, object) do
    format_day_entries(entries, object)
  end

  defp format_day_entries(entries, object) when is_list(entries) and entries != [] do
    Enum.map_join(entries, ", ", &format_time_value(&1, object))
  end

  defp format_day_entries(_day, _object), do: "-"

  defp format_time_value(%TimeValue{time: time, value: value}, object) do
    "#{schedule_time(time)}=#{schedule_entry_value(value, object)}"
  end

  defp format_time_value(entry, _object), do: csv_value(entry, nil)

  defp schedule_time(%BACnetTime{} = time) do
    time
    |> PropertyFormatter.format_value(nil)
    |> String.replace_suffix(".000", "")
  end

  defp schedule_time(time), do: csv_value(time, nil)

  defp schedule_entry_value(nil, _object), do: "NULL"
  defp schedule_entry_value(%Encoding{type: :null}, _object), do: "NULL"

  defp schedule_entry_value(%Encoding{type: :unsigned_integer, value: value}, object) do
    multistate_text(value, object) || Integer.to_string(value)
  end

  defp schedule_entry_value(%Encoding{type: :signed_integer, value: value}, object) do
    multistate_text(value, object) || Integer.to_string(value)
  end

  defp schedule_entry_value(%Encoding{type: :enumerated, value: value}, object) do
    binary_state_text(value, object) || csv_value(value, nil)
  end

  defp schedule_entry_value(%Encoding{type: :boolean, value: value}, object) do
    binary_state_text(value, object) || csv_value(value, nil)
  end

  defp schedule_entry_value(%Encoding{type: :real, value: value}, _object) do
    PropertyFormatter.format_value(value, nil)
  end

  defp schedule_entry_value(%Encoding{value: value}, object) do
    schedule_entry_value(value, object)
  end

  defp schedule_entry_value(value, object) do
    multistate_text(value, object) || binary_state_text(value, object) || csv_value(value, nil)
  end

  defp multistate_text(value, object) when is_map(object) do
    if MultistateState.multistate_object?(object) do
      MultistateState.format_present_value(value, object)
    end
  end

  defp multistate_text(_value, _object), do: nil

  defp binary_state_text(value, object) when is_map(object) do
    normalized =
      case value do
        :active -> true
        :inactive -> false
        other -> other
      end

    case BinaryPV.text_for_value(object, normalized) do
      text when is_binary(text) -> text
      _missing -> nil
    end
  end

  defp binary_state_text(_value, _object), do: nil

  defp schedule_label_object(row) do
    target = referenced_object(row.object, row.device_objects)

    cond do
      label_object?(row.object) -> row.object
      label_object?(target) -> target
      true -> row.object
    end
  end

  defp label_object?(object) when is_map(object) do
    MultistateState.multistate_object?(object) or BinaryPV.has_state_texts?(object) or
      BinaryPV.binary_object?(object)
  end

  defp label_object?(_object), do: false

  defp referenced_object(obj, device_objects) when is_list(device_objects) do
    obj
    |> reference_ids()
    |> Enum.find_value(fn %ObjectIdentifier{type: type, instance: instance} ->
      Enum.find(device_objects, fn candidate ->
        Map.get(candidate, :type) == type and Map.get(candidate, :instance) == instance
      end)
    end)
  end

  defp referenced_object(_obj, _device_objects), do: nil

  defp reference_ids(obj) when is_map(obj) do
    case Map.get(obj, :list_of_object_property_references) do
      %BACnetArray{} = array ->
        array
        |> BACnetArray.to_list()
        |> Enum.flat_map(&reference_id/1)

      refs when is_list(refs) ->
        Enum.flat_map(refs, &reference_id/1)

      _refs ->
        []
    end
  end

  defp reference_ids(_obj), do: []

  defp reference_id(%{object_identifier: %ObjectIdentifier{} = identifier}), do: [identifier]
  defp reference_id(_ref), do: []

  defp weekday_name(1), do: gettext("Montag")
  defp weekday_name(2), do: gettext("Dienstag")
  defp weekday_name(3), do: gettext("Mittwoch")
  defp weekday_name(4), do: gettext("Donnerstag")
  defp weekday_name(5), do: gettext("Freitag")
  defp weekday_name(6), do: gettext("Samstag")
  defp weekday_name(7), do: gettext("Sonntag")
  defp weekday_name(index), do: Integer.to_string(index)

  defp csv_value(%BACnetArray{} = array, _units) do
    array
    |> BACnetArray.to_list()
    |> csv_list()
  end

  defp csv_value(value, _units) when is_list(value), do: csv_list(value)

  defp csv_value(%Encoding{type: type, value: value}, units) do
    "#{PropertyFormatter.encoding_type_label(type)}: #{csv_value(value, units)}"
  end

  defp csv_value(%DateTime{} = value, _units), do: DateTime.to_iso8601(value)
  defp csv_value(%NaiveDateTime{} = value, _units), do: NaiveDateTime.to_iso8601(value)
  defp csv_value(%Date{} = value, _units), do: Date.to_iso8601(value)
  defp csv_value(%Time{} = value, _units), do: Time.to_iso8601(value)

  defp csv_value(%BACnetDateTime{} = value, units),
    do: PropertyFormatter.format_value(value, units)

  defp csv_value(%BACnetDate{} = value, units), do: PropertyFormatter.format_value(value, units)
  defp csv_value(%BACnetTime{} = value, units), do: PropertyFormatter.format_value(value, units)

  defp csv_value(%BACnetTimestamp{} = value, units),
    do: PropertyFormatter.format_value(value, units)

  defp csv_value(%ObjectIdentifier{} = value, units),
    do: PropertyFormatter.format_value(value, units)

  defp csv_value(%PriorityArray{} = value, units),
    do: PropertyFormatter.format_value(value, units)

  defp csv_value(%Recipient{} = value, units), do: PropertyFormatter.format_value(value, units)

  defp csv_value(%RecipientAddress{} = value, units),
    do: PropertyFormatter.format_value(value, units)

  defp csv_value(value, units) when is_struct(value),
    do: csv_struct(Map.from_struct(value), units)

  defp csv_value(value, units) when is_map(value), do: csv_struct(value, units)
  defp csv_value(value, units), do: PropertyFormatter.format_value(value, units)

  defp csv_list(items) do
    texts = Enum.map(items, &csv_value(&1, nil))
    "[" <> Enum.join(texts, ", ") <> "]"
  end

  defp csv_struct(fields, _units) do
    parts =
      fields
      |> Enum.reject(fn {key, _child} -> internal_key?(key) end)
      |> Enum.map(fn {key, child} -> {csv_field_label(key), csv_value(child, nil)} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {label, text} -> "#{label}: #{text}" end)

    "{" <> Enum.join(parts, ", ") <> "}"
  end

  defp csv_field_label(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &csv_capitalize/1)
  end

  defp csv_field_label(key), do: to_string(key)

  defp csv_capitalize(word) do
    case String.split(word, "-") do
      [single] -> String.capitalize(single)
      parts -> Enum.map_join(parts, "-", &String.capitalize/1)
    end
  end

  defp json_value(nil), do: nil
  defp json_value(value) when is_boolean(value), do: value
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value) when is_integer(value), do: value

  defp json_value(value) when is_float(value), do: value

  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json_value(%Date{} = value), do: Date.to_iso8601(value)
  defp json_value(%Time{} = value), do: Time.to_iso8601(value)

  defp json_value(%ObjectIdentifier{type: type, instance: instance}) do
    %{"type" => property_token(type), "instance" => instance}
  end

  defp json_value(%Encoding{value: value}), do: json_value(value)

  defp json_value(%BACnetArray{} = array) do
    array
    |> BACnetArray.to_list()
    |> Enum.map(&json_value/1)
  end

  defp json_value(%PriorityArray{} = array) do
    array
    |> PriorityArray.to_list()
    |> Enum.map(fn
      {priority, value} -> %{"priority" => priority, "value" => json_value(value)}
      value -> json_value(value)
    end)
  end

  defp json_value(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {key, _value} -> internal_key?(key) end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), json_value(value)} end)
  end

  defp json_value(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_value(value)} end)
  end

  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)
  defp json_value({:bitstring, value}), do: json_value(value)

  defp json_value(value) when is_tuple(value) and tuple_size(value) > 0 do
    cond do
      PropertyFormatter.bitstring_value?(value) ->
        value |> Tuple.to_list() |> Enum.map(&json_value/1)

      ip_tuple?(value) ->
        case :inet.ntoa(value) do
          chars when is_list(chars) -> List.to_string(chars)
          _error -> value |> Tuple.to_list() |> Enum.map(&json_value/1)
        end

      tuple_size(value) == 2 and tagged_tuple?(value) ->
        %{"_tag" => Atom.to_string(elem(value, 0)), "value" => json_value(elem(value, 1))}

      true ->
        value |> Tuple.to_list() |> Enum.map(&json_value/1)
    end
  end

  defp json_value(value) when is_binary(value) do
    if String.valid?(value), do: value, else: Text.sanitize_utf8(value) || ""
  end

  defp json_value(value), do: inspect(value, limit: 40)

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_integer(key), do: Integer.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp ip_tuple?(value) when is_tuple(value) and tuple_size(value) in [4, 8] do
    value
    |> Tuple.to_list()
    |> Enum.all?(&is_integer/1)
  end

  defp ip_tuple?(_value), do: false

  defp tagged_tuple?({tag, _value}) when is_atom(tag) and tag not in [true, false, nil], do: true
  defp tagged_tuple?(_value), do: false

  defp csv_cell(""), do: ""
  defp csv_cell(value) when is_binary(value), do: "\"#{String.replace(value, "\"", "\"\"")}\""
  defp csv_cell(value) when is_atom(value), do: Atom.to_string(value)
  defp csv_cell(value), do: to_string(value)

  defp filename(rows, format) do
    ext = Atom.to_string(format)

    case rows |> Enum.map(& &1.device_instance) |> Enum.uniq() do
      [instance] -> "bacview-properties-#{instance}.#{ext}"
      _instances -> "bacview-properties.#{ext}"
    end
  end

  defp mime(:csv), do: @csv_mime
  defp mime(:json), do: @json_mime
end
