defmodule BacView.BACnet.Protocol.UnknownProperty do
  @moduledoc false

  alias BACnet.Protocol.ApplicationTags
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.Text

  # Application-tag primitives that the object UI can edit with a simple control.
  # Excludes constructed/tagged encodings, proprietary blobs, date/time, and object IDs.
  @editable_primitive_types [
    :boolean,
    :enumerated,
    :unsigned_integer,
    :signed_integer,
    :real,
    :double,
    :octet_string,
    :character_string,
    :bitstring
  ]

  @type t :: %{
          type: String.t(),
          display_value: term(),
          formatted: String.t(),
          string_value?: boolean(),
          hex_toggle?: boolean(),
          raw_binary: binary() | nil,
          primitive_editable?: boolean()
        }

  @doc """
  Builds a single-pass presentation of an unknown BACnet property value for the UI.
  """
  @spec present(term()) :: t()
  def present(value) do
    case classify(value) do
      {:encoding_list, binary} ->
        %{
          type: "PROPRIETARY",
          display_value: binary,
          formatted: PropertyFormatter.format_binary_hex(binary),
          string_value?: true,
          hex_toggle?: false,
          raw_binary: binary,
          primitive_editable?: false
        }

      {:encoding_list, :encode_failed, original} ->
        display = PropertyDisplay.build(original)

        %{
          type: PropertyFormatter.property_type(original),
          display_value: original,
          formatted: display.formatted,
          string_value?: false,
          hex_toggle?: false,
          raw_binary: nil,
          primitive_editable?: false
        }

      {:encoding, %Encoding{} = encoding} ->
        present_encoding(encoding)

      {:binary, binary} ->
        formatted = Text.sanitize_utf8(binary)

        %{
          type: PropertyFormatter.property_type(binary),
          display_value: binary,
          formatted: formatted,
          string_value?: true,
          # Bare binaries are treated as character text — no hex toggle.
          hex_toggle?: false,
          raw_binary: binary,
          primitive_editable?: true
        }

      {:other, other} ->
        display = PropertyDisplay.build(other)

        %{
          type: PropertyFormatter.property_type(other),
          display_value: other,
          formatted: display.formatted,
          string_value?: false,
          hex_toggle?: false,
          raw_binary: nil,
          primitive_editable?: other_primitive_editable?(other)
        }
    end
  end

  @doc """
  Returns true when the unknown property row can be edited as a simple primitive.
  """
  @spec primitive_editable?(map() | t()) :: boolean()
  def primitive_editable?(%{primitive_editable?: editable}) when is_boolean(editable),
    do: editable

  def primitive_editable?(_prop), do: false

  defp classify(value) when is_list(value) do
    if encoding_list?(value) do
      case encoding_list_binary(value) do
        {:ok, binary} -> {:encoding_list, binary}
        _other -> {:encoding_list, :encode_failed, value}
      end
    else
      {:other, value}
    end
  end

  defp classify(%Encoding{} = encoding), do: {:encoding, encoding}
  defp classify(value) when is_binary(value), do: {:binary, value}
  defp classify(value), do: {:other, value}

  defp present_encoding(%Encoding{type: :character_string, value: inner} = encoding)
       when is_binary(inner) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: Text.sanitize_utf8(inner),
      string_value?: true,
      hex_toggle?: false,
      raw_binary: inner,
      primitive_editable?: encoding_primitive_editable?(encoding)
    }
  end

  defp present_encoding(%Encoding{type: :octet_string, value: inner} = encoding)
       when is_binary(inner) do
    formatted =
      if Text.printable_text?(inner) do
        inner
      else
        PropertyFormatter.format_binary_hex(inner)
      end

    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: formatted,
      string_value?: true,
      # Octet strings only — and only when default view differs from colon-hex.
      hex_toggle?: PropertyFormatter.hex_display_differs?(formatted, inner),
      raw_binary: inner,
      primitive_editable?: encoding_primitive_editable?(encoding)
    }
  end

  defp present_encoding(%Encoding{encoding: :primitive, value: inner} = encoding)
       when is_binary(inner) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: Text.sanitize_utf8(inner),
      string_value?: true,
      hex_toggle?: false,
      raw_binary: inner,
      primitive_editable?: encoding_primitive_editable?(encoding)
    }
  end

  defp present_encoding(%Encoding{encoding: :primitive, value: inner} = encoding) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: PropertyFormatter.format_value(inner, nil),
      string_value?: false,
      hex_toggle?: false,
      raw_binary: nil,
      primitive_editable?: encoding_primitive_editable?(encoding)
    }
  end

  defp present_encoding(%Encoding{value: inner} = encoding) when is_binary(inner) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: encoding,
      formatted: PropertyDisplay.build(encoding).formatted,
      string_value?: true,
      hex_toggle?: false,
      raw_binary: inner,
      primitive_editable?: false
    }
  end

  defp present_encoding(%Encoding{} = encoding) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: encoding,
      formatted: PropertyDisplay.build(encoding).formatted,
      string_value?: false,
      hex_toggle?: false,
      raw_binary: nil,
      primitive_editable?: false
    }
  end

  defp encoding_primitive_editable?(%Encoding{encoding: :primitive, type: type})
       when type in @editable_primitive_types,
       do: true

  defp encoding_primitive_editable?(_encoding), do: false

  defp other_primitive_editable?(value)
       when is_boolean(value) or is_float(value) or is_integer(value) or is_binary(value),
       do: true

  defp other_primitive_editable?(value) when is_atom(value) and value not in [nil, :unspecified],
    do: true

  defp other_primitive_editable?(value), do: PropertyFormatter.bitstring_value?(value)

  defp encoding_list?(value) when is_list(value) do
    value != [] and Enum.all?(value, &match?(%Encoding{}, &1))
  end

  defp encoding_list_binary(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, <<>>}, fn %Encoding{} = encoding, {:ok, acc} ->
      with {:ok, raw} <- Encoding.to_encoding(encoding),
           {:ok, bytes} <- ApplicationTags.encode(raw) do
        {:cont, {:ok, acc <> bytes}}
      else
        {:error, _reason} = err -> {:halt, err}
      end
    end)
  end
end
