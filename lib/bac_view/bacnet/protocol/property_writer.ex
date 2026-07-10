defmodule BacView.BACnet.Protocol.PropertyWriter do
  @moduledoc """
  Parses user input and builds options for BACnet WriteProperty requests.
  """

  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.PriorityArray
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter

  alias BacView.MapHelpers

  @priority_fields for p <- 1..16, do: String.to_atom("priority_#{p}")

  @default_priority 8

  @spec default_priority() :: 1..16
  def default_priority(), do: @default_priority

  @spec enrich_properties([map()], map() | nil) :: [map()]
  def enrich_properties(properties, object) when is_list(properties) do
    Enum.map(properties, fn prop ->
      prop
      |> enrich_multistate_state_property(object)
      |> enrich_present_value_formatting(object)
      |> maybe_commandable_present_value(object)
      |> then(fn enriched ->
        if Map.get(enriched, :writable, false) do
          MapHelpers.update(enriched, %{writable: true})
        else
          enriched
        end
      end)
    end)
  end

  def enrich_properties(properties, _properties), do: properties

  defp enrich_multistate_state_property(%{property: property} = prop, object)
       when property in [:present_value, :relinquish_default] and is_map(object) do
    if MultistateState.multistate_object?(object) do
      formatted = multistate_state_property_formatted(property, prop, object)
      display = Map.put(prop.value_display, :formatted, formatted)
      options = MultistateState.state_options(object)

      prop
      |> Map.put(:value_display, display)
      |> Map.put(:value_formatted, formatted)
      |> Map.put(:enum_options, options)
      |> Map.put(:type, "INTEGER")
    else
      prop
    end
  end

  defp enrich_multistate_state_property(prop, _object), do: prop

  defp enrich_present_value_formatting(
         %{property: :present_value, value: value, value_display: display} = prop,
         object
       )
       when is_map(object) do
    if MultistateState.multistate_object?(object) do
      prop
    else
      formatted = PropertyFormatter.format_present_value(value, object, prop)
      display = Map.put(display, :formatted, formatted)

      prop
      |> Map.put(:value_display, display)
      |> Map.put(:value_formatted, formatted)
    end
  end

  defp enrich_present_value_formatting(%{property: :present_value} = prop, _object), do: prop

  defp enrich_present_value_formatting(prop, _object), do: prop

  defp multistate_state_property_formatted(:present_value, prop, object),
    do: PropertyFormatter.format_present_value(prop.value, object, prop)

  defp multistate_state_property_formatted(:relinquish_default, prop, object) do
    MultistateState.format_present_value(prop.value, object) ||
      PropertyFormatter.format_value(prop.value, nil)
  end

  defp maybe_commandable_present_value(%{property: :present_value} = prop, object) do
    if commandable_for_ui?(object), do: Map.put(prop, :writable, true), else: prop
  end

  defp maybe_commandable_present_value(prop, _object), do: prop

  @doc false
  @spec commandable_object?(map() | struct() | nil) :: boolean()
  def commandable_object?(object), do: commandable_for_ui?(object)

  @doc false
  @spec commandable_for_ui?(map() | struct() | nil) :: boolean()
  def commandable_for_ui?(nil), do: false

  def commandable_for_ui?(%{commandable: commandable}) when is_boolean(commandable),
    do: commandable

  def commandable_for_ui?(object) when is_map(object), do: has_priority_array?(object)

  def commandable_for_ui?(_nil), do: false

  @doc false
  @spec has_priority_array?(map() | struct()) :: boolean()
  def has_priority_array?(object) when is_map(object) do
    case normalize_priority_array(Map.get(object, :priority_array)) do
      %PriorityArray{} -> true
      _object -> false
    end
  end

  def has_priority_array?(_object), do: false

  @doc false
  @spec priority_write?(map() | struct() | nil, atom() | integer(), pos_integer()) :: boolean()
  def priority_write?(object, :present_value, priority) when priority in 1..16 do
    commandable_for_ui?(object)
  end

  def priority_write?(_object, _property, _priority), do: false

  @doc false
  @spec priority_slot_value(PriorityArray.t(), 1..16) :: term()
  def priority_slot_value(%PriorityArray{} = pa, priority) when priority in 1..16 do
    Map.get(pa, Enum.at(@priority_fields, priority - 1))
  end

  @spec parse_write_params(map(), map()) :: {:ok, term()} | {:error, term()}
  def parse_write_params(params, prop) do
    case Map.get(prop, :value_display) do
      %{kind: :struct, fields: fields} ->
        parse_struct_params(params, prop, fields)

      _params ->
        params
        |> Map.get("value", "")
        |> normalize_param_value()
        |> parse_scalar_value(prop)
    end
  end

  defp parse_scalar_value(value, %{enum_type: enum_type})
       when is_atom(enum_type) and enum_type != nil do
    PropertyEnumeration.parse_value(value, enum_type)
  end

  defp parse_scalar_value(value, %{enum_options: options} = prop)
       when is_list(options) and options != [] do
    parse_input(value, prop)
  end

  defp parse_scalar_value(value, prop) when is_binary(value), do: parse_input(value, prop)

  defp normalize_param_value(values) when is_list(values) do
    values
    |> List.last()
    |> normalize_param_value()
  end

  defp normalize_param_value(value) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  defp normalize_param_value(value) when is_binary(value), do: value
  defp normalize_param_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_param_value(_values), do: ""

  @spec write_opts(map() | struct() | nil, atom() | integer(), pos_integer()) :: keyword()
  def write_opts(object, :present_value, priority) when priority in 1..16 do
    if priority_write?(object, :present_value, priority), do: [priority: priority], else: []
  end

  def write_opts(_object, _property, _priority), do: []

  @spec prop_hint_from_object(map()) :: map()
  def prop_hint_from_object(%{present_value: value} = object) do
    hint = %{
      type: prop_hint_type(object, value),
      value: value,
      property: :present_value,
      units: Map.get(object, :units)
    }

    if MultistateState.multistate_object?(object) do
      Map.put(hint, :enum_options, MultistateState.state_options(object))
    else
      hint
    end
  end

  def prop_hint_from_object(_object), do: %{type: "REAL", value: nil}

  defp prop_hint_type(object, value) do
    if MultistateState.multistate_object?(object), do: "INTEGER", else: value_type_label(value)
  end

  @doc false
  @spec active_priority_info(map() | term(), term(), map() | nil) :: %{
          active_priority: 1..16 | nil,
          active_priority_value_formatted: String.t() | nil
        }
  def active_priority_info(obj, units \\ nil, object_context \\ nil)

  def active_priority_info(%{} = obj, units, object_context) do
    context = object_context || obj
    resolved_units = units || Map.get(obj, :units)

    case Map.get(obj, :priority_array) do
      %PriorityArray{} = pa ->
        active_priority_from_array(pa, resolved_units, context)

      other ->
        active_priority_from_array(
          normalize_priority_array(other),
          resolved_units,
          context
        )
    end
  end

  defp active_priority_from_array(priority_array, units, object_context) do
    case normalize_priority_array(priority_array) do
      %PriorityArray{} = pa ->
        case PriorityArray.get_value(pa) do
          {priority, value} ->
            %{
              active_priority: priority,
              active_priority_value_formatted: format_priority_value(value, units, object_context)
            }

          nil ->
            empty_active_priority_info()
        end

      _priority_array ->
        empty_active_priority_info()
    end
  end

  defp format_priority_value(value, units, object_context) do
    PropertyFormatter.format_present_value(value, object_context) ||
      PropertyFormatter.format_value(value, units)
  end

  @doc false
  @spec normalize_priority_array(term()) :: PriorityArray.t() | nil
  def normalize_priority_array(%PriorityArray{} = pa), do: pa

  def normalize_priority_array(%BACnetArray{} = array), do: PriorityArray.from_array(array)

  def normalize_priority_array(list) when is_list(list), do: PriorityArray.from_list(list)

  def normalize_priority_array(_pa), do: nil

  defp empty_active_priority_info() do
    %{active_priority: nil, active_priority_value_formatted: nil}
  end

  defp value_type_label(v) when is_float(v), do: "REAL"
  defp value_type_label(v) when is_integer(v), do: "INTEGER"
  defp value_type_label(v) when is_boolean(v), do: "BOOLEAN"
  defp value_type_label(v) when is_atom(v), do: "ENUMERATED"
  defp value_type_label(_v), do: "REAL"

  defp parse_struct_params(params, prop, fields) do
    property = prop.property

    if Enum.all?(fields, &(&1.kind == :boolean)) do
      parse_boolean_struct(params, prop, fields, property)
    else
      {:error, :unsupported_struct}
    end
  end

  defp parse_boolean_struct(params, prop, fields, property) do
    values =
      Map.new(fields, fn field ->
        param_key = struct_param_key(property, field.key)
        checked = Map.get(params, param_key) in [true, "true", "on", "1"]
        {field.key, checked}
      end)

    case Map.get(prop, :value) do
      %_params{} = current ->
        {:ok, struct(current, values)}

      _params ->
        {:error, :unsupported_struct}
    end
  end

  defp struct_param_key(property, key) when is_atom(property) and is_atom(key),
    do: "#{property}_#{key}"

  defp struct_param_key(property, key), do: "#{property}_#{key}"

  @spec parse_input(String.t(), map() | nil) :: {:ok, term()} | {:error, term()}
  def parse_input(value, prop) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        {:error, :empty_value}

      nil_reset?(trimmed) ->
        {:ok, nil}

      true ->
        parse_typed_value(trimmed, prop)
    end
  end

  defp nil_reset?(s),
    do: String.downcase(s) in ["null", "nil", "none", "—", "-", "relinquish", "reset"]

  defp parse_typed_value(s, %{type: "BOOLEAN"}),
    do: parse_boolean(s)

  defp parse_typed_value(s, %{type: "REAL"}),
    do: parse_float(s)

  defp parse_typed_value(s, %{type: "INTEGER"}),
    do: parse_integer(s)

  defp parse_typed_value(s, %{type: "ENUMERATED", value: value}) when is_atom(value),
    do: parse_enum(s, value)

  defp parse_typed_value(s, %{value: value}) when is_boolean(value),
    do: parse_boolean(s)

  defp parse_typed_value(s, %{value: value}) when is_float(value),
    do: parse_float(s)

  defp parse_typed_value(s, %{value: value}) when is_integer(value),
    do: parse_integer(s)

  defp parse_typed_value(s, %{value: value}) when is_atom(value),
    do: parse_enum(s, value)

  defp parse_typed_value(s, _prop), do: parse_number(s)

  defp parse_boolean(s) do
    case String.downcase(s) do
      "true" -> {:ok, true}
      "1" -> {:ok, true}
      "active" -> {:ok, :active}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      "inactive" -> {:ok, :inactive}
      _params -> {:error, :invalid_boolean}
    end
  end

  defp parse_float(s) do
    case Float.parse(s) do
      {f, ""} -> {:ok, f}
      _s -> {:error, :invalid_number}
    end
  end

  defp parse_integer(s) do
    case Integer.parse(s) do
      {i, ""} -> {:ok, i}
      _s -> {:error, :invalid_number}
    end
  end

  defp parse_number(s) do
    case Float.parse(s) do
      {f, ""} -> {:ok, f}
      _s -> parse_integer(s)
    end
  end

  defp parse_enum(s, current) when is_atom(current) do
    atom =
      try do
        String.to_existing_atom(String.downcase(s))
      rescue
        ArgumentError -> nil
      end

    if atom, do: {:ok, atom}, else: {:ok, s}
  end

  @doc false
  @spec values_match?(term(), term()) :: boolean()
  def values_match?(nil, _read), do: true

  def values_match?(written, read) when written == read, do: true

  def values_match?(written, read) when is_float(written) and is_float(read) do
    abs(written - read) < 1.0e-4
  end

  def values_match?(written, read) when is_integer(written) and is_float(read) do
    values_match?(written * 1.0, read)
  end

  def values_match?(written, read) when is_float(written) and is_integer(read) do
    values_match?(written, read * 1.0)
  end

  def values_match?(written, read) when is_list(written) and is_list(read) do
    length(written) == length(read) and
      Enum.all?(Enum.zip(written, read), fn {w, r} -> values_match?(w, r) end)
  end

  def values_match?(%BACnetArray{} = written, %BACnetArray{} = read) do
    written.fixed_size == read.fixed_size and
      BACnetArray.size(written) == BACnetArray.size(read) and
      bacnet_array_items_match?(written, read)
  end

  def values_match?(%{__struct__: module} = written, %{__struct__: module} = read) do
    written
    |> Map.from_struct()
    |> Enum.all?(fn {key, w_val} -> values_match?(w_val, Map.get(read, key)) end)
  end

  def values_match?(%{__struct__: _nil}, %{__struct__: _read}), do: false

  def values_match?(_written, _read), do: false

  defp bacnet_array_items_match?(written, read) do
    size = BACnetArray.size(written)

    if size == 0 do
      true
    else
      Enum.all?(1..size, fn index ->
        case {BACnetArray.get_item(written, index), BACnetArray.get_item(read, index)} do
          {{:ok, w}, {:ok, r}} -> values_match?(w, r)
          _written -> false
        end
      end)
    end
  end
end
