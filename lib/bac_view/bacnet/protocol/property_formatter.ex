defmodule BacView.BACnet.Protocol.PropertyFormatter do
  @moduledoc """
  Formats BACnet property values for display.
  """

  alias BACnet.Protocol.ApplicationTags.Encoding

  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PriorityArray
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress

  alias BacView.BACnet.Protocol.BacnetCalendarFormat
  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.Text

  @max_float_decimals 10

  @binary_object_types [
    :binary_input,
    :binary_output,
    :binary_value,
    :binary_lighting_output
  ]

  @analog_object_types [
    :analog_input,
    :analog_output,
    :analog_value,
    :large_analog_value
  ]

  @spec binary_object_type?(atom()) :: boolean()
  def binary_object_type?(type) when type in @binary_object_types, do: true
  def binary_object_type?(_type), do: false

  @spec boolean_present_value?(map() | nil, map() | nil) :: boolean()
  def boolean_present_value?(object, prop \\ nil)

  def boolean_present_value?(%{type: type}, _prop), do: binary_object_type?(type)

  def boolean_present_value?(_object, %{bac_type: :boolean}), do: true
  def boolean_present_value?(_object, %{type: "BOOLEAN"}), do: true
  def boolean_present_value?(_object, _nil), do: false

  @spec coerce_present_value(term(), map() | nil, map() | nil) :: term()
  def coerce_present_value(value, object, prop \\ nil)

  def coerce_present_value(value, object, prop)
      when value in [0, 1] and is_map(object) do
    if boolean_present_value?(object, prop), do: value == 1, else: value
  end

  def coerce_present_value(value, _object, _prop), do: value

  @spec format_edit_value(term(), map() | nil, map() | nil) :: String.t()
  def format_edit_value(nil, _object, _prop), do: ""

  def format_edit_value(value, _object, _prop) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  def format_edit_value(value, _object, _prop) when is_atom(value), do: Atom.to_string(value)
  def format_edit_value(value, _object, _prop) when is_binary(value), do: value

  def format_edit_value(value, _object, _prop) when is_integer(value),
    do: Integer.to_string(value)

  def format_edit_value(value, object, prop) when is_float(value) do
    if editable_real_present_value?(value, object, prop) do
      format_present_float(value, object && Map.get(object, :resolution))
    else
      format_float(value)
    end
  end

  def format_edit_value(_value, _object, _prop), do: ""

  @spec format_present_value(term(), map() | nil, map() | nil) :: String.t()
  def format_present_value(value, object, prop \\ nil) do
    coerced = coerce_present_value(value, object, prop)
    units = object && Map.get(object, :units)

    base =
      cond do
        MultistateState.multistate_object?(object) ->
          MultistateState.format_present_value(coerced, object) ||
            format_value(coerced, units)

        real_present_value?(coerced, object, prop) ->
          format_real_present_value(coerced, units, object)

        true ->
          format_value(coerced, units)
      end

    base
  end

  @spec format_float(float()) :: String.t()
  def format_float(value) when is_float(value) do
    format_float(value, nil)
  end

  @spec format_float(float(), term()) :: String.t()
  def format_float(value, resolution) when is_float(value) do
    case decimal_places_from_resolution(resolution) do
      nil ->
        value
        |> :erlang.float_to_binary(decimals: @max_float_decimals)
        |> trim_trailing_zeros()

      decimals ->
        :erlang.float_to_binary(value, decimals: decimals)
    end
  end

  @spec format_value(term(), term()) :: String.t()
  def format_value(nil, _units), do: "—"

  def format_value(value, units) when is_number(value) and not is_nil(units) do
    case EngineeringUnits.symbol(units) do
      "" -> format_number(value)
      symbol -> "#{format_number(value)} #{symbol}"
    end
  end

  def format_value(value, _units) when is_float(value), do: format_float(value)

  def format_value(value, _units) when is_integer(value), do: Integer.to_string(value)
  def format_value(value, _units) when is_boolean(value), do: if(value, do: "true", else: "false")
  def format_value(value, _units) when is_binary(value), do: Text.sanitize_utf8(value)
  def format_value(value, _units) when is_atom(value), do: Atom.to_string(value)

  def format_value(value, _units) when is_list(value) do
    Enum.map_join(value, ", ", &format_value(&1, nil))
  end

  def format_value(%PriorityArray{} = value, _units) do
    case PriorityArray.get_value(value) do
      {priority, active} -> "#{format_value(active, nil)} (P#{priority})"
      nil -> "—"
    end
  end

  def format_value(%Encoding{type: type, value: value}, units) do
    "#{encoding_type_label(type)}: #{format_value(value, units)}"
  end

  def format_value(%BACnetDateTime{} = value, _units), do: BacnetCalendarFormat.format(value)
  def format_value(%BACnetDate{} = value, _units), do: BacnetCalendarFormat.format(value)
  def format_value(%BACnetTime{} = value, _units), do: BacnetCalendarFormat.format(value)
  def format_value(%BACnetTimestamp{} = value, _units), do: BacnetCalendarFormat.format(value)

  def format_value(%ObjectIdentifier{type: type, instance: instance}, _units),
    do: "#{type}:#{instance}"

  def format_value(%RecipientAddress{network: network, address: address}, _units) do
    "#{network}/#{format_mac_address(address)}"
  end

  def format_value(%Recipient{type: :device, device: %ObjectIdentifier{} = device}, _units) do
    format_value(device, nil)
  end

  def format_value(%Recipient{type: :address, address: %RecipientAddress{} = address}, _units) do
    format_value(address, nil)
  end

  def format_value(%_nil{} = value, units) do
    case Map.get(value, :value) do
      nil -> PropertyDisplay.summary(PropertyDisplay.build(value))
      inner -> format_value(inner, units)
    end
  end

  def format_value(value, _units) when is_map(value) do
    inspect(value, limit: 80, printable_limit: 80)
  end

  def format_value(value, _units), do: inspect(value, limit: 80)

  @min_port 1
  @max_port 65_535

  @doc """
  Formats a BACnet data-link address (octet string) for display.

  Six-byte BACnet/IP addresses are shown as `IPv4:port` when the port is in the
  valid UDP/TCP range (1..65535). All other binary addresses are shown as
  uppercase hex byte groups. `:broadcast` is rendered as the literal string
  `broadcast`.
  """
  @spec format_binary_hex(binary()) :: String.t()
  def format_binary_hex(binary) when is_binary(binary), do: format_hex_address(binary)

  @spec format_mac_address(binary() | :broadcast) :: String.t()
  def format_mac_address(:broadcast), do: "broadcast"

  def format_mac_address(binary) when is_binary(binary) do
    case byte_size(binary) do
      0 ->
        ""

      6 ->
        format_six_byte_address(binary)

      _broadcast ->
        format_hex_address(binary)
    end
  end

  defp format_six_byte_address(<<a, b, c, d, port_hi, port_lo>>) do
    port = port_hi * 256 + port_lo

    if port in @min_port..@max_port do
      "#{a}.#{b}.#{c}.#{d}:#{port}"
    else
      format_hex_address(<<a, b, c, d, port_hi, port_lo>>)
    end
  end

  defp format_hex_address(binary) do
    binary
    |> Base.encode16(case: :upper)
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.map_join(":", &Enum.join(&1, ""))
  end

  @encoding_primitive_types [
    :null,
    :boolean,
    :unsigned_integer,
    :signed_integer,
    :real,
    :double,
    :octet_string,
    :character_string,
    :bitstring,
    :enumerated,
    :date,
    :time,
    :object_identifier
  ]

  @spec encoding_primitive_types() :: [atom()]
  def encoding_primitive_types(), do: @encoding_primitive_types

  @spec encoding_type_label(atom() | nil) :: String.t()
  def encoding_type_label(nil), do: "CONSTRUCTED"

  def encoding_type_label(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  @spec property_type(term()) :: String.t()
  def property_type(nil), do: "—"
  def property_type(value) when is_float(value), do: "REAL"
  def property_type(value) when is_integer(value), do: "INTEGER"
  def property_type(value) when is_boolean(value), do: "BOOLEAN"
  def property_type(value) when is_binary(value), do: "CHARACTER STRING"
  def property_type(value) when is_atom(value), do: "ENUMERATED"
  def property_type(value) when is_list(value), do: "ARRAY"
  def property_type(_value), do: "STRUCT"

  defp format_number(value) when is_float(value), do: format_float(value)
  defp format_number(value) when is_integer(value), do: Integer.to_string(value)

  defp real_present_value?(value, object, prop) when is_number(value) do
    analog_object?(object) or real_present_value_prop?(prop)
  end

  defp real_present_value?(_value3, _object, _value), do: false

  defp editable_real_present_value?(value, object, prop) when is_float(value) do
    present_value_property?(prop) and real_present_value?(value, object, prop)
  end

  defp present_value_property?(%{property: property})
       when property in [:present_value, :relinquish_default],
       do: true

  defp present_value_property?(_prop), do: false

  defp analog_object?(%{type: type}) when type in @analog_object_types, do: true
  defp analog_object?(_analog_object), do: false

  defp real_present_value_prop?(%{bac_type: :real}), do: true
  defp real_present_value_prop?(%{type: "REAL"}), do: true
  defp real_present_value_prop?(_real_present_value_prop), do: false

  defp format_real_present_value(value, units, _object) when is_integer(value) do
    with_units(Integer.to_string(value), units)
  end

  defp format_real_present_value(value, units, object) when is_float(value) do
    resolution = object && Map.get(object, :resolution)
    formatted = format_present_float(value, resolution)
    with_units(formatted, units)
  end

  defp format_present_float(value, resolution) when is_float(value) do
    case decimal_places_from_resolution(resolution) do
      nil ->
        value
        |> :erlang.float_to_binary(decimals: @max_float_decimals)
        |> trim_unneeded_decimals()

      decimals ->
        :erlang.float_to_binary(value, decimals: decimals)
    end
  end

  defp with_units(formatted, units) do
    case EngineeringUnits.symbol(units) do
      "" -> formatted
      symbol -> "#{formatted} #{symbol}"
    end
  end

  @spec decimal_places_from_resolution(term()) :: non_neg_integer() | nil
  def decimal_places_from_resolution(resolution) when is_integer(resolution) and resolution >= 1,
    do: 0

  def decimal_places_from_resolution(resolution) when is_integer(resolution) and resolution > 0 do
    decimal_places_from_resolution(resolution * 1.0)
  end

  def decimal_places_from_resolution(resolution)
      when is_float(resolution) and resolution >= 1.0,
      do: 0

  def decimal_places_from_resolution(resolution) when is_float(resolution) and resolution > 0 do
    resolution
    |> :erlang.float_to_binary(decimals: @max_float_decimals)
    |> String.split(".", parts: 2)
    |> case do
      [_whole] ->
        0

      [_whole, fraction] ->
        fraction
        |> String.trim_trailing("0")
        |> String.length()
    end
  end

  def decimal_places_from_resolution(_resolution), do: nil

  defp trim_trailing_zeros(str) do
    if String.contains?(str, ".") do
      [whole, fraction] = String.split(str, ".", parts: 2)
      trimmed = String.trim_trailing(fraction, "0")
      fraction = if trimmed == "", do: "0", else: trimmed
      whole <> "." <> fraction
    else
      str
    end
  end

  defp trim_unneeded_decimals(str) do
    if String.contains?(str, ".") do
      str
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    else
      str
    end
  end
end
