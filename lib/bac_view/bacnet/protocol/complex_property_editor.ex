defmodule BacView.BACnet.Protocol.ComplexPropertyEditor do
  @moduledoc false

  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.DailySchedule
  alias BACnet.Protocol.DeviceObjectPropertyRef
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectPropertyRef
  alias BACnet.Protocol.PriorityArray
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Protocol.SpecialEvent

  alias BACnet.Protocol.ApplicationTags.Encoding

  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.StructFieldTypes

  @type form_field :: %{
          path: String.t(),
          label: String.t(),
          value: String.t(),
          readonly: boolean(),
          enum_options: [%{value: atom(), label: String.t()}] | nil
        }

  @spec editor_type(term()) :: atom()
  def editor_type(%DailySchedule{}), do: :daily_schedule
  def editor_type(%SpecialEvent{}), do: :special_event
  def editor_type(%BACnetDateTime{}), do: :date_time
  def editor_type(%BACnetDate{}), do: :date
  def editor_type(%BACnetTime{}), do: :time
  def editor_type(%BACnetTimestamp{}), do: :timestamp
  def editor_type(%ObjectPropertyRef{}), do: :object_property_ref
  def editor_type(%DeviceObjectPropertyRef{}), do: :device_object_property_ref
  def editor_type(%ObjectIdentifier{}), do: :object_identifier
  def editor_type(%BACnetArray{}), do: :bacnet_array
  def editor_type(%Encoding{}), do: :encoding
  def editor_type(%_editor_type_arg1{}), do: :generic
  def editor_type(_editor_type_arg1), do: :generic

  @spec form_fields(term()) :: [form_field()]
  def form_fields(value) do
    value
    |> collect_form_fields([], [])
    |> Enum.reverse()
  end

  @spec initial_field_params([form_field()]) :: %{String.t() => String.t()}
  def initial_field_params(fields) do
    Map.new(fields, fn %{path: path, value: value} -> {path, value} end)
  end

  @doc """
  Strips LiveView `_unused_*` form keys that appear when only a subset of inputs change.
  """
  @spec normalize_field_params(map()) :: map()
  def normalize_field_params(fields) when is_map(fields) do
    fields
    |> Enum.reject(fn {key, _value} -> unused_field_key?(key) end)
    |> Map.new()
  end

  @spec apply_form_fields(map(), term()) :: {:ok, term()} | {:error, term()}
  def apply_form_fields(params, template) do
    case normalize_field_params(Map.get(params, "field", %{})) do
      fields when map_size(fields) == 0 ->
        {:ok, template}

      fields ->
        finalize_apply_result(
          Enum.reduce_while(Enum.sort(Map.keys(fields)), {:ok, template}, fn path,
                                                                             {:ok, current} ->
            with {:ok, segments} <- parse_path(path),
                 {:ok, updated} <- update_in_structure(current, segments, Map.get(fields, path)) do
              {:cont, {:ok, updated}}
            else
              {:error, _params} = err -> {:halt, err}
            end
          end)
        )
    end
  end

  @spec encode_json(term()) :: {:ok, String.t()} | {:error, term()}
  def encode_json(value) do
    Jason.encode(encode(value), pretty: true)
  end

  @spec decode_json(String.t(), term()) :: {:ok, term()} | {:error, term()}
  def decode_json(json, template) when is_binary(json) do
    trimmed = String.trim(json)

    if trimmed == "" do
      {:error, :empty_value}
    else
      with {:ok, decoded} <- Jason.decode(trimmed) do
        decode(decoded, template)
      end
    end
  end

  defp collect_form_fields(value, path_rev, acc, parent \\ nil, field_key \\ nil)

  defp collect_form_fields(%Encoding{} = encoding, path_rev, acc, _parent, _field_key) do
    acc =
      [
        build_encoding_kind_field(encoding.encoding, [:encoding | path_rev])
        | acc
      ]

    acc =
      [
        build_encoding_type_field(encoding.type, [:type | path_rev])
        | acc
      ]

    extras_path = [:tag_number, :extras | path_rev]

    acc =
      [
        build_form_field(
          Keyword.get(encoding.extras, :tag_number),
          extras_path,
          encoding,
          :tag_number,
          field_label_at([:extras | path_rev], "Tag Number")
        )
        | acc
      ]

    collect_form_fields(encoding.value, [:value | path_rev], acc, encoding, :value)
  end

  defp collect_form_fields(%BACnetArray{} = array, path_rev, acc, _parent, field_key) do
    array
    |> bacnet_array_elements()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item, index}, acc ->
      collect_form_fields(item, [index | path_rev], acc, array, field_key)
    end)
  end

  defp collect_form_fields(
         %ObjectIdentifier{type: type, instance: instance},
         path_rev,
         acc,
         _value,
         _path
       ) do
    [
      build_form_field(
        type,
        [:type | path_rev],
        %ObjectIdentifier{type: type, instance: instance},
        :type,
        field_label_at(path_rev, "Type")
      ),
      build_form_field(
        instance,
        [:instance | path_rev],
        %ObjectIdentifier{type: type, instance: instance},
        :instance,
        field_label_at(path_rev, "Instance")
      )
      | acc
    ]
  end

  defp collect_form_fields(%_value{} = struct, path_rev, acc, _path, _acc) do
    Enum.reduce(Map.from_struct(struct), acc, fn {key, value}, acc ->
      collect_form_fields(value, [key | path_rev], acc, struct, key)
    end)
  end

  defp collect_form_fields(list, path_rev, acc, parent, field_key) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item, index}, acc ->
      collect_form_fields(item, [index | path_rev], acc, parent, field_key)
    end)
  end

  defp collect_form_fields({tag, value}, path_rev, acc, parent, field_key) when is_atom(tag) do
    [
      build_form_field(
        value,
        path_rev,
        parent,
        field_key,
        field_label_at(path_rev, "Value (#{tag})")
      )
      | acc
    ]
  end

  defp collect_form_fields(value, path_rev, acc, parent, field_key) do
    [build_form_field(value, path_rev, parent, field_key, nil) | acc]
  end

  defp build_form_field(value, path_rev, parent, field_key, label_override) do
    enum_type =
      if parent && field_key do
        StructFieldTypes.enum_type_for_field(parent, field_key)
      end

    %{
      path: path_string(path_rev),
      label: label_override || field_label_at(path_rev, nil),
      value: value_to_string(value),
      readonly: false,
      enum_options: enum_options_for(value, enum_type, parent, field_key)
    }
  end

  defp build_encoding_kind_field(encoding, path_rev) do
    %{
      path: path_string(path_rev),
      label: field_label_at(path_rev, nil),
      value: value_to_string(encoding),
      readonly: false,
      enum_options: encoding_kind_options()
    }
  end

  defp build_encoding_type_field(type, path_rev) do
    %{
      path: path_string(path_rev),
      label: field_label_at(path_rev, nil),
      value: value_to_string(type),
      readonly: false,
      enum_options: encoding_type_options()
    }
  end

  defp encoding_kind_options() do
    Enum.map([:primitive, :tagged, :constructed], fn kind ->
      %{value: kind, label: PropertyFormatter.encoding_type_label(kind)}
    end)
  end

  defp encoding_type_options() do
    Enum.map(PropertyFormatter.encoding_primitive_types(), fn type ->
      %{value: type, label: PropertyFormatter.encoding_type_label(type)}
    end)
  end

  defp enum_options_for(_value, enum_type, _parent, _field_key) when is_atom(enum_type) do
    case PropertyEnumeration.options(enum_type) do
      [] -> nil
      options -> options
    end
  end

  defp update_in_structure(%Encoding{} = data, [:encoding], string_value) do
    with {:ok, encoding} <- decode_encoding_kind(string_value) do
      extras = strip_tag_number_for_primitive(encoding, data.extras)
      {:ok, %{data | encoding: encoding, extras: extras}}
    end
  end

  defp update_in_structure(%Encoding{} = data, [:type], string_value) do
    with {:ok, type} <- decode_encoding_type_field(string_value, data.type) do
      {:ok, %{data | type: type}}
    end
  end

  defp update_in_structure(%Encoding{} = data, [:extras, :tag_number], string_value) do
    with {:ok, extras} <- apply_tag_number_change(data.extras, string_value) do
      {:ok, %{data | extras: extras}}
    end
  end

  defp update_in_structure(%Encoding{} = data, [:value], string_value) do
    with {:ok, parsed} <- parse_encoding_value(data.type, data.value, string_value) do
      {:ok, %{data | value: parsed}}
    end
  end

  defp update_in_structure({tag, current}, [], string_value) when is_atom(tag) do
    case parse_field_value(current, string_value) do
      {:ok, parsed} -> {:ok, {tag, parsed}}
      other -> other
    end
  end

  defp update_in_structure(data, [], string_value) do
    parse_field_value(data, string_value)
  end

  defp update_in_structure(data, [key], string_value) do
    with {:ok, child} <- get_child(data, key),
         {:ok, parsed} <-
           parse_field_value(child, string_value, StructFieldTypes.enum_type_for_field(data, key)) do
      map_child(data, key, parsed)
    end
  end

  defp update_in_structure(data, [key | rest], string_value) do
    case get_child(data, key) do
      {:ok, child} ->
        with {:ok, updated_child} <- update_in_structure(child, rest, string_value) do
          map_child(data, key, updated_child)
        end

      {:error, _data} = err ->
        err
    end
  end

  defp get_child(data, key) when is_list(data) and is_integer(key) do
    case Enum.at(data, key) do
      nil -> {:error, :invalid_path}
      child -> {:ok, child}
    end
  end

  defp get_child(%BACnetArray{} = array, key) when is_integer(key) and key >= 0 do
    case BACnetArray.get_item(array, key + 1) do
      {:ok, child} -> {:ok, child}
      :error -> {:error, :invalid_path}
    end
  end

  defp get_child(extras, key) when is_list(extras) and is_atom(key) do
    {:ok, Keyword.get(extras, key)}
  end

  defp get_child(%_data{} = struct, key), do: {:ok, Map.get(struct, key)}
  defp get_child(_data, _key), do: {:error, :invalid_path}

  defp map_child(list, key, value) when is_list(list) and is_integer(key) do
    {:ok, List.replace_at(list, key, value)}
  end

  defp map_child(%BACnetArray{} = array, key, value) when is_integer(key) and key >= 0 do
    case BACnetArray.set_item(array, key + 1, value) do
      {:ok, updated} -> {:ok, updated}
      {:error, _list} = err -> err
    end
  end

  defp map_child(extras, key, value) when is_list(extras) and is_atom(key) do
    {:ok, Keyword.put(extras, key, value)}
  end

  defp map_child(%_list{} = struct, key, value), do: {:ok, struct(struct, [{key, value}])}
  defp map_child(_list, _key, _value), do: {:error, :invalid_path}

  defp parse_field_value(current, string_value, enum_type \\ nil)

  defp parse_field_value(current, string_value, enum_type)
       when is_atom(enum_type) and enum_type != nil do
    case PropertyEnumeration.parse_value(string_value, enum_type) do
      {:ok, atom} ->
        {:ok, atom}

      {:error, :empty_value} ->
        if is_nil(current), do: {:ok, nil}, else: {:error, :empty_value}

      {:error, _current} ->
        {:error, :invalid_enum}
    end
  end

  defp parse_field_value(current, string_value, nil) do
    trimmed = String.trim(string_value)

    cond do
      trimmed == "" and is_nil(current) -> {:ok, nil}
      trimmed == "" -> {:error, :empty_value}
      trimmed == "unspecified" -> {:ok, :unspecified}
      is_boolean(current) -> parse_boolean(trimmed)
      is_integer(current) -> parse_integer(trimmed)
      is_float(current) -> parse_float(trimmed)
      is_atom(current) and not is_nil(current) -> decode_atom_field(trimmed)
      true -> {:ok, trimmed}
    end
  end

  defp parse_boolean(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _value -> {:error, :invalid_boolean}
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _value -> {:error, :invalid_number}
    end
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _value -> {:error, :invalid_number}
    end
  end

  defp value_to_string(nil), do: ""
  defp value_to_string(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_to_string(value) when is_integer(value), do: Integer.to_string(value)

  defp value_to_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 10)

  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value), do: inspect(value, limit: 200)

  defp path_string(path_rev) do
    path_rev
    |> Enum.reverse()
    |> Enum.map_join(".", &segment_to_string/1)
  end

  defp segment_to_string(index) when is_integer(index), do: Integer.to_string(index)
  defp segment_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp segment_to_string(other), do: to_string(other)

  defp parse_path(path) do
    case Enum.reduce_while(String.split(path, "."), {:ok, []}, fn segment, {:ok, acc} ->
           case parse_path_segment(segment) do
             {:ok, part} -> {:cont, {:ok, [part | acc]}}
             {:error, _path} = err -> {:halt, err}
           end
         end) do
      {:ok, segments} -> {:ok, Enum.reverse(segments)}
      err -> err
    end
  end

  defp unused_field_key?(key) when is_binary(key), do: String.starts_with?(key, "_unused_")
  defp unused_field_key?(_key), do: false

  defp parse_path_segment(segment) do
    case Integer.parse(segment) do
      {index, ""} ->
        {:ok, index}

      _segment ->
        {:ok, String.to_existing_atom(segment)}
    end
  rescue
    ArgumentError -> {:error, :invalid_path}
  end

  defp field_label_at(path_rev, suffix) do
    labels =
      path_rev
      |> Enum.reverse()
      |> Enum.map(&segment_label/1)
      |> Enum.reject(&(&1 == ""))

    base = Enum.join(labels, " · ")

    cond do
      base == "" and is_binary(suffix) -> suffix
      base == "" -> "Value"
      is_binary(suffix) -> base <> " · " <> suffix
      true -> base
    end
  end

  defp segment_label(index) when is_integer(index), do: "[#{index + 1}]"

  defp segment_label(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp encode(%Encoding{type: type, value: value, encoding: encoding, extras: extras}) do
    %{
      "encoding" => Atom.to_string(encoding),
      "type" => if(type, do: Atom.to_string(type), else: nil),
      "extras" => encode_encoding_extras(extras),
      "value" => encode(value)
    }
  end

  defp encode(%ObjectIdentifier{type: type, instance: instance}) do
    %{"type" => Atom.to_string(type), "instance" => instance}
  end

  defp encode(%PriorityArray{} = array) do
    array
    |> PriorityArray.to_list()
    |> Enum.map(fn
      {priority, value} -> %{"priority" => priority, "value" => encode(value)}
      value -> encode(value)
    end)
  end

  defp encode(%BACnetArray{} = array),
    do: array |> bacnet_array_elements() |> Enum.map(&encode/1)

  defp encode(%_value{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), encode(value)} end)
    |> Map.new()
  end

  defp encode({tag, value}) when is_atom(tag),
    do: %{"_tag" => Atom.to_string(tag), "value" => encode(value)}

  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  defp encode(nil), do: nil
  defp encode(value) when is_atom(value), do: Atom.to_string(value)
  defp encode(value), do: value

  defp decode(value, %Encoding{} = template) when is_map(value),
    do: decode_encoding_map(value, template)

  defp decode(value, %Encoding{type: type, value: template_value} = template) do
    with {:ok, decoded} <- decode(value, template_value) do
      rebuild_encoding(type, decoded, template)
    end
  end

  defp decode(value, %ObjectIdentifier{}), do: decode_object_identifier(value)
  defp decode(value, %PriorityArray{} = template), do: decode_priority_array(value, template)

  defp decode(value, %BACnetArray{} = template), do: decode_bacnet_array(value, template)

  defp decode(value, %BACnetDate{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %BACnetTime{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %BACnetDateTime{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %BACnetTimestamp{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %Recipient{} = template), do: decode_recipient(value, template)
  defp decode(value, %_json{} = template), do: decode_struct_fields(value, template)

  defp decode(value, template) when is_list(template), do: decode_list(value, template)
  defp decode(value, _template) when is_integer(value), do: {:ok, value}
  defp decode(value, _template) when is_float(value) or is_boolean(value), do: {:ok, value}

  defp decode(value, template) when is_binary(value) and is_atom(template),
    do: decode_atom_field(value)

  defp decode(value, _template) when is_binary(value), do: {:ok, value}
  defp decode(value, nil) when value in [nil, "nil"], do: {:ok, nil}
  defp decode(nil, _template), do: {:ok, nil}

  defp decode(%{"_tag" => tag, "value" => inner}, template) when is_binary(tag) do
    with {:ok, tag_atom} <- decode_existing_atom(tag),
         {:ok, decoded} <- decode(inner, template_value_template(template, tag_atom)) do
      {:ok, {tag_atom, decoded}}
    end
  end

  defp decode(_value, _template), do: {:error, :invalid_json_value}

  defp decode_struct_fields(map, %_map{} = template) when is_map(map) do
    fields = Map.from_struct(template)

    with :ok <- reject_unknown_json_fields(map, fields) do
      decode_known_struct_fields(map, fields, template)
    end
  end

  defp decode_struct_fields(_value, _template), do: {:error, :invalid_struct_json}

  defp bacnet_array_elements(%BACnetArray{size: 0}), do: []

  defp bacnet_array_elements(%BACnetArray{} = array) do
    Enum.map(1..BACnetArray.size(array), fn index ->
      case BACnetArray.get_item(array, index) do
        {:ok, item} -> item
        :error -> BACnetArray.get_default(array)
      end
    end)
  end

  defp bacnet_array_item_template(%BACnetArray{} = array, json_items) do
    case bacnet_array_elements(array) do
      [item | _array] when is_struct(item) ->
        item

      _array ->
        case BACnetArray.get_default(array) do
          default when is_struct(default) -> default
          _array -> infer_array_item_template(json_items)
        end
    end
  end

  defp infer_array_item_template([item | _item]) when is_map(item) do
    keys = MapSet.new(Map.keys(item))

    cond do
      MapSet.subset?(
        MapSet.new(["device_identifier", "object_identifier", "property_identifier"]),
        keys
      ) ->
        %DeviceObjectPropertyRef{
          object_identifier: %ObjectIdentifier{type: :analog_input, instance: 0},
          property_identifier: :present_value,
          property_array_index: nil,
          device_identifier: nil
        }

      MapSet.subset?(MapSet.new(["object_identifier", "property_identifier"]), keys) ->
        %ObjectPropertyRef{
          object_identifier: %ObjectIdentifier{type: :analog_input, instance: 0},
          property_identifier: :present_value,
          property_array_index: nil
        }

      true ->
        nil
    end
  end

  defp infer_array_item_template(_item), do: nil

  defp decode_bacnet_array(list, %BACnetArray{fixed_size: fixed_size} = template)
       when is_list(list) and is_integer(fixed_size) do
    actual = length(list)

    if actual != fixed_size do
      {:error, {:fixed_bacnet_array_size, fixed_size, actual}}
    else
      decode_bacnet_array_items(list, template)
    end
  end

  defp decode_bacnet_array(list, %BACnetArray{} = template) when is_list(list) do
    decode_bacnet_array_items(list, template)
  end

  defp decode_bacnet_array(_value, _template), do: {:error, :invalid_list_json}

  defp decode_bacnet_array_items(list, %BACnetArray{} = template) do
    item_templates = bacnet_array_elements(template)
    default_item_template = bacnet_array_item_template(template, list)

    with {:ok, decoded_items} <- decode_array_items(list, item_templates, default_item_template) do
      rebuild_bacnet_array(decoded_items, template, default_item_template)
    end
  end

  defp decode_array_items(list, item_templates, default_item_template) do
    case Enum.reduce_while(Enum.with_index(list), {:ok, []}, fn {item, index}, {:ok, acc} ->
           item_template = Enum.at(item_templates, index, default_item_template)

           case decode(item, item_template) do
             {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
             {:error, _list} = err -> {:halt, err}
           end
         end) do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      err -> err
    end
  end

  defp rebuild_bacnet_array(items, %BACnetArray{fixed_size: nil} = template, item_template) do
    default = array_rebuild_default(template, item_template)
    {:ok, BACnetArray.from_list(items, false, default)}
  end

  defp rebuild_bacnet_array(
         items,
         %BACnetArray{fixed_size: fixed_size} = template,
         _item_template
       )
       when is_integer(fixed_size) do
    default = BACnetArray.get_default(template)
    base = BACnetArray.new(fixed_size, default)

    Enum.reduce_while(Enum.with_index(items, 1), {:ok, base}, fn {item, index}, {:ok, array} ->
      case BACnetArray.set_item(array, index, item) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _items} = err -> {:halt, err}
      end
    end)
  end

  defp array_rebuild_default(_template, item_template) when is_struct(item_template),
    do: item_template

  defp array_rebuild_default(template, _item_template), do: BACnetArray.get_default(template)

  defp decode_recipient(map, %Recipient{} = fallback) when is_map(map) do
    template =
      case Map.get(map, "type") do
        "device" ->
          %Recipient{
            type: :device,
            address: nil,
            device: recipient_device_template(fallback)
          }

        "address" ->
          %Recipient{
            type: :address,
            device: nil,
            address: recipient_address_template(fallback)
          }

        _map ->
          fallback
      end

    decode_struct_fields(map, template)
  end

  defp decode_recipient(_value, _template), do: {:error, :invalid_struct_json}

  defp recipient_device_template(%Recipient{device: %ObjectIdentifier{} = device}), do: device

  defp recipient_device_template(_recipient_device_template_arg1),
    do: %ObjectIdentifier{type: :device, instance: 0}

  defp recipient_address_template(%Recipient{address: %RecipientAddress{} = address}), do: address

  defp recipient_address_template(_recipient_address_template_arg1),
    do: %RecipientAddress{network: 0, address: :broadcast}

  defp decode_known_struct_fields(map, fields, %_map{} = template) do
    case Enum.reduce_while(fields, {:ok, %{}}, fn {key, field_template}, {:ok, acc} ->
           string_key = Atom.to_string(key)

           case Map.fetch(map, string_key) do
             :error ->
               {:cont, {:ok, Map.put(acc, key, field_template)}}

             {:ok, raw} ->
               case decode(raw, field_template) do
                 {:ok, decoded} -> {:cont, {:ok, Map.put(acc, key, decoded)}}
                 {:error, _map} = err -> {:halt, err}
               end
           end
         end) do
      {:ok, attrs} -> {:ok, struct(template.__struct__, attrs)}
      err -> err
    end
  end

  defp reject_unknown_json_fields(map, fields) when is_map(map) do
    known_keys = fields |> Map.keys() |> Enum.map(&Atom.to_string/1) |> MapSet.new()

    case Enum.reject(Map.keys(map), &MapSet.member?(known_keys, &1)) do
      [] -> :ok
      unknown -> {:error, {:unknown_json_fields, Enum.sort(unknown)}}
    end
  end

  defp decode_object_identifier(%{"type" => type, "instance" => instance}) when is_binary(type) do
    with {:ok, type_atom} <- PropertyEnumeration.parse_value(type, :object_type) do
      {:ok, %ObjectIdentifier{type: type_atom, instance: instance}}
    end
  end

  defp decode_object_identifier(_type), do: {:error, :invalid_object_identifier}

  defp decode_list(list, template) when is_list(list) and is_list(template) do
    default_item_template = List.first(template) || recipient_list_item_template(template)

    case Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
           item_template = list_item_template(item, default_item_template, template)

           case decode(item, item_template) do
             {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
             {:error, _list} = err -> {:halt, err}
           end
         end) do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      err -> err
    end
  end

  defp decode_list(list, _template) when is_list(list), do: {:ok, list}
  defp decode_list(_list, _template), do: {:error, :invalid_list_json}

  defp list_item_template(%{"type" => type}, default, list) when is_binary(type) do
    if recipient_list?(list) do
      recipient_template_for_type(type, default)
    else
      default
    end
  end

  defp list_item_template(_item, default, _list), do: default

  defp recipient_template_for_type("device", %Recipient{} = fallback) do
    %Recipient{
      type: :device,
      address: nil,
      device: recipient_device_template(fallback)
    }
  end

  defp recipient_template_for_type("address", %Recipient{} = fallback) do
    %Recipient{
      type: :address,
      device: nil,
      address: recipient_address_template(fallback)
    }
  end

  defp recipient_template_for_type(_type, default), do: default

  defp recipient_list?([%Recipient{} | _rest]), do: true
  defp recipient_list?(_value), do: false

  defp recipient_list_item_template([
         %Recipient{} = recipient | _recipient_list_item_template_arg1
       ]),
       do: recipient

  defp recipient_list_item_template(_recipient_list_item_template_arg1), do: nil

  defp decode_priority_array(list, %PriorityArray{} = template) when is_list(list) do
    slots =
      Enum.reduce_while(1..16, {:ok, %{}}, fn priority, {:ok, acc} ->
        field = priority_field_atom(priority)
        current = Map.get(template, field)

        encoded_item =
          Enum.find(list, fn
            %{"priority" => ^priority} = item -> item
            _list -> nil
          end)

        case encoded_item do
          %{"value" => raw} ->
            case decode(raw, current) do
              {:ok, decoded} -> {:cont, {:ok, Map.put(acc, field, decoded)}}
              err -> {:halt, err}
            end

          _list ->
            {:cont, {:ok, Map.put(acc, field, current)}}
        end
      end)

    case slots do
      {:ok, attrs} -> {:ok, struct(PriorityArray, attrs)}
      err -> err
    end
  end

  defp decode_priority_array(value, template),
    do: decode_list(value, PriorityArray.to_list(template))

  defp decode_atom_field(value) do
    case decode_existing_atom(value) do
      {:ok, atom} -> {:ok, atom}
      {:error, _value} -> {:ok, value}
    end
  end

  defp decode_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_atom}
  end

  defp template_value_template(_template, :real), do: 0.0
  defp template_value_template(_template, :enumerated), do: :active
  defp template_value_template(_template, :boolean), do: false
  defp template_value_template(_template, :unsigned_integer), do: 0
  defp template_value_template(_template, :signed_integer), do: 0
  defp template_value_template(_template, :character_string), do: ""
  defp template_value_template(template, _tag), do: template

  defp finalize_apply_result({:ok, %Encoding{} = value}), do: finalize_encoding(value)
  defp finalize_apply_result(result), do: result

  defp decode_encoding_map(map, %Encoding{} = template) when is_map(map) do
    with :ok <- reject_unknown_encoding_json_fields(map),
         {:ok, encoding_kind} <-
           decode_encoding_kind_field(Map.get(map, "encoding"), template.encoding),
         {:ok, type} <- decode_encoding_type_field(Map.get(map, "type"), template.type),
         {:ok, extras} <- decode_encoding_extras(Map.get(map, "extras"), template.extras),
         value_template <-
           encoding_value_template(type, template.type, template.value),
         {:ok, value} <- decode(Map.get(map, "value"), value_template) do
      finalize_encoding(%{
        template
        | encoding: encoding_kind,
          type: type,
          extras: extras,
          value: value
      })
    end
  end

  defp reject_unknown_encoding_json_fields(map) do
    known = MapSet.new(["type", "value", "encoding", "extras"])

    case Enum.reject(Map.keys(map), &MapSet.member?(known, &1)) do
      [] -> :ok
      unknown -> {:error, {:unknown_json_fields, Enum.sort(unknown)}}
    end
  end

  defp decode_encoding_type_field(nil, template_type), do: {:ok, template_type}

  defp decode_encoding_type_field("", _template_type), do: {:ok, nil}

  defp decode_encoding_type_field(type, _template_type) when is_binary(type) do
    decode_encoding_type(type)
  end

  defp decode_encoding_kind_field(nil, template_kind), do: {:ok, template_kind}

  defp decode_encoding_kind_field(kind, _template_kind) when is_binary(kind) do
    decode_encoding_kind(kind)
  end

  defp decode_encoding_kind(string_value) when is_binary(string_value) do
    case decode_existing_atom(string_value) do
      {:ok, kind} when kind in [:primitive, :tagged, :constructed] -> {:ok, kind}
      {:ok, _nil} -> {:error, :invalid_encoding_kind}
      {:error, _nil} = err -> err
    end
  end

  defp decode_encoding_extras(nil, template_extras), do: {:ok, template_extras}

  defp decode_encoding_extras(map, template_extras) when is_map(map) do
    case Map.fetch(map, "tag_number") do
      :error ->
        {:ok, template_extras}

      {:ok, raw} ->
        with {:ok, tag_number} <- decode_optional_integer(raw) do
          {:ok, put_tag_number_extra(template_extras, tag_number)}
        end
    end
  end

  defp decode_encoding_extras(_value, template_extras), do: {:ok, template_extras}

  defp decode_optional_integer(nil), do: {:ok, nil}
  defp decode_optional_integer(value) when is_integer(value), do: {:ok, value}

  defp decode_optional_integer(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      case Integer.parse(trimmed) do
        {int, ""} -> {:ok, int}
        _nil -> {:error, :invalid_number}
      end
    end
  end

  defp strip_tag_number_for_primitive(:primitive, extras), do: Keyword.delete(extras, :tag_number)
  defp strip_tag_number_for_primitive(_encoding, extras), do: extras

  defp apply_tag_number_change(extras, string_value) do
    case decode_optional_integer(string_value) do
      {:ok, nil} -> {:ok, Keyword.delete(extras, :tag_number)}
      {:ok, tag} -> {:ok, Keyword.put(extras, :tag_number, tag)}
      {:error, _extras} = err -> err
    end
  end

  defp put_tag_number_extra(extras, nil), do: Keyword.delete(extras, :tag_number)
  defp put_tag_number_extra(extras, tag), do: Keyword.put(extras, :tag_number, tag)

  defp encode_encoding_extras(extras) when is_list(extras) do
    extras
    |> Keyword.take([:tag_number])
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
  end

  defp decode_encoding_type(string_value) when is_binary(string_value) do
    case decode_existing_atom(string_value) do
      {:ok, type} ->
        if type in PropertyFormatter.encoding_primitive_types(),
          do: {:ok, type},
          else: {:error, :invalid_encoding_type}

      {:error, _nil} = err ->
        err
    end
  end

  defp encoding_value_template(type, type, value), do: value

  defp encoding_value_template(type, _template_type, _value),
    do: template_value_template(nil, type)

  defp rebuild_encoding(type, value, %Encoding{} = template) when is_atom(type) do
    finalize_encoding(%{template | type: type, value: value})
  end

  defp rebuild_encoding(nil, value, %Encoding{} = template) do
    finalize_encoding(%{template | value: value})
  end

  defp finalize_encoding(%Encoding{} = encoding) do
    safe_finalize_encoding(encoding)
  rescue
    e in KeyError ->
      if e.key == :tag_number,
        do: {:error, :missing_tag_number},
        else: {:error, :invalid_encoding}
  end

  defp safe_finalize_encoding(%Encoding{} = encoding) do
    case Encoding.to_encoding(encoding) do
      {:ok, raw} ->
        case Encoding.create(raw, extras_to_create_opts(encoding.extras)) do
          {:ok, %Encoding{} = created} ->
            {:ok, preserve_encoding_metadata(created, encoding)}

          {:error, _encoding} = err ->
            err
        end

      {:error, _encoding} ->
        {:error, :invalid_encoding}
    end
  end

  defp extras_to_create_opts(extras) when is_list(extras),
    do: Keyword.take(extras, [:context, :encoder])

  defp preserve_encoding_metadata(%Encoding{} = created, %Encoding{} = template) do
    extras =
      if template.extras == [] do
        created.extras
      else
        template.extras
      end

    %{created | extras: extras}
  end

  defp parse_encoding_value(:boolean, _current, string_value) do
    parse_boolean(String.trim(string_value))
  end

  defp parse_encoding_value(type, _current, string_value)
       when type in [:real, :double] do
    parse_float(String.trim(string_value))
  end

  defp parse_encoding_value(type, _current, string_value)
       when type in [:unsigned_integer, :signed_integer, :enumerated] do
    parse_integer(String.trim(string_value))
  end

  defp parse_encoding_value(:null, _current, string_value) do
    if String.trim(string_value) in ["", "null"],
      do: {:ok, nil},
      else: {:error, :invalid_encoding_value}
  end

  defp parse_encoding_value(_type, current, string_value) do
    parse_field_value(current, string_value)
  end

  defp priority_field_atom(priority) when priority in 1..16,
    do: String.to_existing_atom("priority_#{priority}")
end
