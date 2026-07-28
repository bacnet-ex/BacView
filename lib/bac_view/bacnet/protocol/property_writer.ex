defmodule BacView.BACnet.Protocol.PropertyWriter do
  @moduledoc """
  Parses user input and builds options for BACnet WriteProperty requests.
  """

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.PriorityArray
  alias BacView.BACnet.Protocol.BinaryPV
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter

  @priority_fields for p <- 1..16, do: String.to_atom("priority_#{p}")

  @default_priority 8

  @spec default_priority() :: 1..16
  def default_priority(), do: @default_priority

  @spec enrich_properties([map()], map() | nil) :: [map()]
  def enrich_properties(properties, object) when is_list(properties) do
    object = merge_binary_texts_from_properties(object, properties)

    Enum.map(properties, fn prop ->
      prop
      |> enrich_multistate_state_property(object)
      |> enrich_binary_value_property(object)
      |> enrich_present_value_formatting(object)
      |> maybe_commandable_present_value(object)
      |> then(fn enriched ->
        if Map.get(enriched, :writable, false) do
          Map.merge(enriched, %{writable: true})
        else
          enriched
        end
      end)
    end)
  end

  def enrich_properties(properties, _properties), do: properties

  defp merge_binary_texts_from_properties(object, properties)
       when is_map(object) and is_list(properties) do
    texts =
      Enum.reduce(properties, %{}, fn
        %{property: :inactive_text, value: value}, acc ->
          case BinaryPV.normalize_text(value) do
            nil -> acc
            text -> Map.put(acc, :inactive_text, text)
          end

        %{property: :active_text, value: value}, acc ->
          case BinaryPV.normalize_text(value) do
            nil -> acc
            text -> Map.put(acc, :active_text, text)
          end

        _prop, acc ->
          acc
      end)

    Map.merge(object, texts)
  end

  defp merge_binary_texts_from_properties(object, _properties), do: object

  defp enrich_multistate_state_property(%{property: property} = prop, object)
       when property in [:present_value, :relinquish_default] and is_map(object) do
    if MultistateState.multistate_object?(object) do
      formatted = multistate_state_property_formatted(property, prop, object)
      display = Map.put(prop.value_display, :formatted, formatted)

      options =
        object
        |> MultistateState.state_options()
        |> PropertyEnumeration.with_current_value_option(Map.get(prop, :value))

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

  defp enrich_binary_value_property(%{property: property} = prop, object)
       when property in [:present_value, :relinquish_default, :priority_array] and is_map(object) do
    if BinaryPV.binary_object?(object) and not MultistateState.multistate_object?(object) do
      enrich_binary_property_display(prop, object)
    else
      prop
    end
  end

  defp enrich_binary_value_property(prop, _object), do: prop

  defp enrich_binary_property_display(%{property: :priority_array, value: value} = prop, object) do
    display = PropertyDisplay.build(value, object: object)

    prop
    |> Map.put(:value_display, display)
    |> Map.put(:value_formatted, display.formatted)
  end

  defp enrich_binary_property_display(
         %{property: property, value: value, value_display: display} = prop,
         object
       )
       when property in [:present_value, :relinquish_default] do
    formatted =
      case property do
        :present_value ->
          PropertyFormatter.format_present_value(value, object, prop)

        :relinquish_default ->
          BinaryPV.format_value(value, object) ||
            PropertyFormatter.format_value(value, nil)
      end

    display = Map.put(display, :formatted, formatted)

    prop
    |> Map.put(:value_display, display)
    |> Map.put(:value_formatted, formatted)
  end

  defp enrich_binary_property_display(prop, _object), do: prop

  defp enrich_present_value_formatting(
         %{property: :present_value, value: value, value_display: display} = prop,
         object
       )
       when is_map(object) do
    if MultistateState.multistate_object?(object) or BinaryPV.binary_object?(object) do
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
        value =
          params
          |> Map.get("value", "")
          |> normalize_param_value()

        if hex_encoding?(params) do
          parse_hex_input(value)
        else
          parse_scalar_value(value, prop)
        end
    end
  end

  defp hex_encoding?(%{"encoding" => encoding}) when encoding in ["hex", :hex], do: true
  defp hex_encoding?(_params), do: false

  @doc """
  Parses a hex string (`AA:BB:00` or `AABB00`) into a binary.
  """
  @spec parse_hex_input(String.t()) :: {:ok, binary()} | {:error, term()}
  def parse_hex_input(value) when is_binary(value) do
    cleaned =
      value
      |> String.trim()
      |> String.replace(~r/[\s:_\-]/, "")
      |> String.downcase()

    cond do
      cleaned == "" ->
        {:error, :empty_value}

      rem(String.length(cleaned), 2) != 0 ->
        {:error, :invalid_hex}

      not Regex.match?(~r/^[0-9a-f]+$/, cleaned) ->
        {:error, :invalid_hex}

      true ->
        case Base.decode16(cleaned, case: :lower) do
          {:ok, binary} -> {:ok, binary}
          :error -> {:error, :invalid_hex}
        end
    end
  end

  defp parse_scalar_value(value, %{enum_type: enum_type})
       when is_atom(enum_type) and enum_type != nil do
    PropertyEnumeration.parse_value(value, enum_type)
  end

  defp parse_scalar_value(value, %{enum_options: options})
       when is_list(options) and options != [] do
    PropertyEnumeration.parse_option_value(value, options)
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
      options =
        object
        |> MultistateState.state_options()
        |> PropertyEnumeration.with_current_value_option(value)

      Map.put(hint, :enum_options, options)
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

  defp format_priority_value(value, _units, object_context) do
    PropertyFormatter.format_present_value(value, object_context)
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

  defp value_type_label(v) do
    if PropertyFormatter.bitstring_value?(v), do: "BITSTRING", else: "REAL"
  end

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
    do: String.downcase(s) in ["null", "nil", "none", "-", "-", "relinquish", "reset"]

  defp parse_typed_value(s, %{type: "BOOLEAN"}),
    do: parse_boolean(s)

  defp parse_typed_value(s, %{type: "BITSTRING"} = prop),
    do: parse_bitstring_input(s, prop)

  defp parse_typed_value(s, %{type: "REAL"}),
    do: parse_float(s)

  defp parse_typed_value(s, %{type: "DOUBLE"}),
    do: parse_float(s)

  defp parse_typed_value(s, %{type: "INTEGER"}),
    do: parse_integer(s)

  defp parse_typed_value(s, %{type: "UNSIGNED INTEGER"}),
    do: parse_integer(s)

  defp parse_typed_value(s, %{type: "SIGNED INTEGER"}),
    do: parse_integer(s)

  defp parse_typed_value(s, %{type: "CHARACTER STRING"}),
    do: {:ok, s}

  defp parse_typed_value(s, %{bac_type: :string}),
    do: {:ok, s}

  # Text-mode octet writes (printable) keep the string bytes. Opaque octets are
  # submitted with encoding=hex and handled by parse_hex_input/1 above.
  defp parse_typed_value(s, %{type: "OCTET STRING"}), do: {:ok, s}
  defp parse_typed_value(s, %{bac_type: :octet_string}), do: {:ok, s}

  # Unknown props keep raw Encoding. Prefer wire integers; when the property id is a
  # known constant type (often the same atom, e.g. :notify_type), also accept names.
  defp parse_typed_value(s, %{type: "ENUMERATED", value: %Encoding{}} = prop),
    do: parse_unknown_enumerated(s, prop)

  defp parse_typed_value(s, %{type: "ENUMERATED"}),
    do: parse_enumerated_input(s)

  defp parse_typed_value(s, %{value: value}) when is_binary(value),
    do: {:ok, s}

  defp parse_typed_value(s, %{value: %Encoding{value: value}}) when is_binary(value),
    do: {:ok, s}

  defp parse_typed_value(s, %{value: value}) when is_boolean(value),
    do: parse_boolean(s)

  defp parse_typed_value(s, %{value: %Encoding{value: value}}) when is_boolean(value),
    do: parse_boolean(s)

  defp parse_typed_value(s, %{value: value} = prop) do
    scalar = unwrap_encoding_value(value)

    if PropertyFormatter.bitstring_value?(scalar) do
      parse_bitstring_input(s, Map.put(prop, :value, scalar))
    else
      parse_typed_value_by_scalar(s, scalar)
    end
  end

  defp parse_typed_value(s, _prop), do: parse_number(s)

  defp unwrap_encoding_value(%Encoding{value: inner}), do: inner
  defp unwrap_encoding_value(value), do: value

  defp parse_enumerated_integer(s) when is_binary(s) do
    trimmed = String.trim(s)

    case Integer.parse(trimmed) do
      {i, ""} when i >= 0 -> {:ok, i}
      {_neg, ""} -> {:error, :invalid_enum}
      _other -> {:error, :invalid_enum}
    end
  end

  defp parse_unknown_enumerated(s, prop) when is_binary(s) and is_map(prop) do
    trimmed = String.trim(s)

    if trimmed == "" do
      {:error, :empty_value}
    else
      case parse_enumerated_integer(trimmed) do
        {:ok, _int} = ok ->
          ok

        {:error, :invalid_enum} ->
          resolve_enumerated_name(trimmed, Map.get(prop, :property))
      end
    end
  end

  # Resolve a constant name to its integer when property id is also a Constants type
  # (e.g. :notify_type / :event_state). Returns the integer for Encoding wire form.
  defp resolve_enumerated_name(trimmed, property) when is_atom(property) do
    case existing_atom(String.downcase(trimmed)) do
      nil ->
        {:error, :invalid_enum}

      atom ->
        case Constants.by_name(property, atom) do
          {:ok, int} when is_integer(int) and int >= 0 -> {:ok, int}
          _error -> {:error, :invalid_enum}
        end
    end
  end

  defp resolve_enumerated_name(_trimmed, _property), do: {:error, :invalid_enum}

  # Returns an existing atom, or nil when the name is not an atom yet.
  # Do not use is_atom/1 on the result: nil is an atom in the BEAM type system.
  defp existing_atom(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  defp parse_enumerated_input(s) do
    trimmed = String.trim(s)

    if trimmed == "" do
      {:error, :empty_value}
    else
      case parse_enumerated_integer(trimmed) do
        {:ok, _value} = ok ->
          ok

        {:error, :invalid_enum} ->
          # Named atoms help known-property casting. Bare strings are never valid.
          case existing_atom(String.downcase(trimmed)) do
            nil -> {:error, :invalid_enum}
            atom -> {:ok, atom}
          end
      end
    end
  end

  @doc """
  Prepares a parsed scalar for WriteProperty.

  Unknown / proprietary properties often arrive as primitive `Encoding` values and
  integer property identifiers require an `Encoding` payload for bacstack.
  """
  @spec prepare_write_value(term(), map()) :: {:ok, term()} | {:error, term()}
  def prepare_write_value(value, prop) when is_map(prop) do
    case Map.get(prop, :value) do
      %Encoding{encoding: :primitive, type: :enumerated} = encoding ->
        prepare_enumerated_encoding(encoding, value, Map.get(prop, :property))

      %Encoding{encoding: :primitive, type: type} = encoding
      when type in [
             :boolean,
             :unsigned_integer,
             :signed_integer,
             :real,
             :double,
             :octet_string,
             :character_string,
             :bitstring
           ] ->
        {:ok, %{encoding | value: value}}

      %Encoding{} ->
        {:error, :not_primitive}

      _other ->
        prepare_write_value_for_property_id(value, prop)
    end
  end

  def prepare_write_value(value, _prop), do: {:ok, value}

  # bacstack ApplicationTags encode only non-neg integers for :enumerated.
  defp prepare_enumerated_encoding(encoding, value, _property)
       when is_integer(value) and value >= 0 do
    {:ok, %{encoding | value: value}}
  end

  defp prepare_enumerated_encoding(encoding, value, property)
       when is_atom(value) and is_atom(property) do
    case Constants.by_name(property, value) do
      {:ok, int} when is_integer(int) and int >= 0 ->
        {:ok, %{encoding | value: int}}

      _error ->
        {:error, :invalid_enum}
    end
  end

  defp prepare_enumerated_encoding(_encoding, _value, _property), do: {:error, :invalid_enum}

  defp prepare_write_value_for_property_id(value, %{property: property} = prop)
       when is_integer(property) do
    case type_atom_from_label(Map.get(prop, :type)) || infer_primitive_type(value) do
      nil ->
        {:error, :unknown_write_type}

      type ->
        Encoding.create({type, value})
    end
  end

  defp prepare_write_value_for_property_id(value, _prop), do: {:ok, value}

  defp type_atom_from_label("BOOLEAN"), do: :boolean
  defp type_atom_from_label("ENUMERATED"), do: :enumerated
  defp type_atom_from_label("UNSIGNED INTEGER"), do: :unsigned_integer
  defp type_atom_from_label("SIGNED INTEGER"), do: :signed_integer
  defp type_atom_from_label("INTEGER"), do: :signed_integer
  defp type_atom_from_label("REAL"), do: :real
  defp type_atom_from_label("DOUBLE"), do: :double
  defp type_atom_from_label("OCTET STRING"), do: :octet_string
  defp type_atom_from_label("CHARACTER STRING"), do: :character_string
  defp type_atom_from_label("BITSTRING"), do: :bitstring
  defp type_atom_from_label(_type), do: nil

  defp infer_primitive_type(value) when is_boolean(value), do: :boolean
  defp infer_primitive_type(value) when is_float(value), do: :real
  defp infer_primitive_type(value) when is_integer(value), do: :unsigned_integer
  defp infer_primitive_type(value) when is_binary(value), do: :character_string
  defp infer_primitive_type(value) when is_atom(value), do: :enumerated

  defp infer_primitive_type(value),
    do: if(PropertyFormatter.bitstring_value?(value), do: :bitstring)

  defp parse_typed_value_by_scalar(s, value) when is_float(value), do: parse_float(s)
  defp parse_typed_value_by_scalar(s, value) when is_integer(value), do: parse_integer(s)
  defp parse_typed_value_by_scalar(s, value) when is_atom(value), do: parse_enum(s, value)
  defp parse_typed_value_by_scalar(s, _value), do: parse_number(s)

  defp parse_bitstring_input(s, prop) do
    expected_size = bitstring_expected_size(Map.get(prop, :value))
    PropertyFormatter.parse_bitstring(s, expected_size)
  end

  defp bitstring_expected_size({:bitstring, value}) when is_tuple(value), do: tuple_size(value)
  defp bitstring_expected_size(value) when is_tuple(value), do: tuple_size(value)

  defp bitstring_expected_size(%{__struct__: _module, type: :bitstring, value: value})
       when is_tuple(value),
       do: tuple_size(value)

  defp bitstring_expected_size(_value), do: nil

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

  defp parse_enum(s, _current) when is_binary(s), do: parse_enumerated_input(s)

  @doc false
  @spec values_match?(term(), term()) :: boolean()
  def values_match?(written, read), do: values_match?(written, read, nil)

  @doc false
  @spec values_match?(term(), term(), atom() | integer() | nil) :: boolean()
  def values_match?(nil, _read, _property), do: true

  def values_match?(written, read, _property) when written == read, do: true

  def values_match?(written, read, _property) when is_float(written) and is_float(read) do
    abs(written - read) < 1.0e-4
  end

  def values_match?(written, read, property) when is_integer(written) and is_float(read) do
    values_match?(written * 1.0, read, property)
  end

  def values_match?(written, read, property) when is_float(written) and is_integer(read) do
    values_match?(written, read * 1.0, property)
  end

  def values_match?(written, read, property) when is_list(written) and is_list(read) do
    length(written) == length(read) and
      Enum.all?(Enum.zip(written, read), fn {w, r} -> values_match?(w, r, property) end)
  end

  def values_match?(written, read, _property)
      when is_tuple(written) and is_tuple(read) and tuple_size(written) == tuple_size(read) do
    PropertyFormatter.bitstring_value?(written) and PropertyFormatter.bitstring_value?(read) and
      written == read
  end

  def values_match?(%Encoding{value: written}, %Encoding{value: read}, property),
    do: values_match?(written, read, property)

  def values_match?(%Encoding{value: written}, read, property),
    do: values_match?(written, read, property)

  def values_match?(written, %Encoding{value: read}, property),
    do: values_match?(written, read, property)

  # Written integer / read atom (or reverse): common when Encoding write uses wire
  # integers but read_property unpacks BACnet constants back to atoms.
  def values_match?(written, read, property)
      when is_atom(property) and
             ((is_integer(written) and is_atom(read)) or (is_atom(written) and is_integer(read))) do
    constant_enum_equivalent?(property, written, read)
  end

  def values_match?(%BACnetArray{} = written, %BACnetArray{} = read, property) do
    written.fixed_size == read.fixed_size and
      BACnetArray.size(written) == BACnetArray.size(read) and
      bacnet_array_items_match?(written, read, property)
  end

  def values_match?(%{__struct__: module} = written, %{__struct__: module} = read, property) do
    written
    |> Map.from_struct()
    |> Enum.all?(fn {key, w_val} -> values_match?(w_val, Map.get(read, key), property) end)
  end

  def values_match?(%{__struct__: _written}, %{__struct__: _read}, _property), do: false

  def values_match?(_written, _read, _property), do: false

  defp constant_enum_equivalent?(type, atom, int)
       when is_atom(type) and is_atom(atom) and is_integer(int) and int >= 0 do
    case Constants.by_name(type, atom) do
      {:ok, ^int} -> true
      _error -> false
    end
  end

  defp constant_enum_equivalent?(type, int, atom)
       when is_atom(type) and is_integer(int) and is_atom(atom) do
    constant_enum_equivalent?(type, atom, int)
  end

  defp constant_enum_equivalent?(_type, _left, _right), do: false

  defp bacnet_array_items_match?(written, read, property) do
    size = BACnetArray.size(written)

    if size == 0 do
      true
    else
      Enum.all?(1..size, fn index ->
        case {BACnetArray.get_item(written, index), BACnetArray.get_item(read, index)} do
          {{:ok, w}, {:ok, r}} -> values_match?(w, r, property)
          _written -> false
        end
      end)
    end
  end
end
