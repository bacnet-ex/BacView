defmodule BacView.BACnet.Protocol.UnknownProperty do
  @moduledoc false

  alias BACnet.Protocol.ApplicationTags
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.Text

  @type t :: %{
          type: String.t(),
          display_value: term(),
          formatted: String.t(),
          string_value?: boolean(),
          hex_toggle?: boolean(),
          raw_binary: binary() | nil
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
          raw_binary: binary
        }

      {:encoding_list, :encode_failed, original} ->
        display = PropertyDisplay.build(original)

        %{
          type: PropertyFormatter.property_type(original),
          display_value: original,
          formatted: display.formatted,
          string_value?: false,
          hex_toggle?: false,
          raw_binary: nil
        }

      {:encoding, %Encoding{} = encoding} ->
        present_encoding(encoding)

      {:binary, binary} ->
        %{
          type: PropertyFormatter.property_type(binary),
          display_value: binary,
          formatted: Text.sanitize_utf8(binary),
          string_value?: true,
          hex_toggle?: not Text.printable_text?(binary),
          raw_binary: binary
        }

      {:other, other} ->
        display = PropertyDisplay.build(other)

        %{
          type: PropertyFormatter.property_type(other),
          display_value: other,
          formatted: display.formatted,
          string_value?: false,
          hex_toggle?: false,
          raw_binary: nil
        }
    end
  end

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
      hex_toggle?: not Text.printable_text?(inner),
      raw_binary: inner
    }
  end

  defp present_encoding(%Encoding{type: :octet_string, value: inner} = encoding)
       when is_binary(inner) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: PropertyFormatter.format_binary_hex(inner),
      string_value?: true,
      hex_toggle?: not Text.printable_text?(inner),
      raw_binary: inner
    }
  end

  defp present_encoding(%Encoding{encoding: :primitive, value: inner} = encoding)
       when is_binary(inner) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: Text.sanitize_utf8(inner),
      string_value?: true,
      hex_toggle?: not Text.printable_text?(inner),
      raw_binary: inner
    }
  end

  defp present_encoding(%Encoding{encoding: :primitive, value: inner} = encoding) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: inner,
      formatted: PropertyFormatter.format_value(inner, nil),
      string_value?: false,
      hex_toggle?: false,
      raw_binary: nil
    }
  end

  defp present_encoding(%Encoding{value: inner} = encoding) when is_binary(inner) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: encoding,
      formatted: PropertyDisplay.build(encoding).formatted,
      string_value?: true,
      hex_toggle?: not Text.printable_text?(inner),
      raw_binary: inner
    }
  end

  defp present_encoding(%Encoding{} = encoding) do
    %{
      type: PropertyFormatter.property_type(encoding),
      display_value: encoding,
      formatted: PropertyDisplay.build(encoding).formatted,
      string_value?: false,
      hex_toggle?: false,
      raw_binary: nil
    }
  end

  defp encoding_list?(value) when is_list(value) do
    value != [] and Enum.all?(value, &match?(%Encoding{}, &1))
  end

  defp encoding_list?(_value), do: false

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
