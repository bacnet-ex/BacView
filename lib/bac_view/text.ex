defmodule BacView.Text do
  @moduledoc false

  @replacement "\uFFFD"

  @doc """
  Ensures a binary is valid UTF-8 for JSON/LiveView **text** serialization.

  Tries a Latin-1 reinterpretation first (common for BACnet CharacterStrings),
  then replaces remaining invalid bytes.

  **Do not** use this on opaque BACnet octet strings (MAC addresses, etc.).
  Latin-1 expansion changes byte identity (e.g. `0x82` → `0xC2 0x82`).
  """
  @spec sanitize_utf8(binary() | nil) :: binary() | nil
  def sanitize_utf8(nil), do: nil

  def sanitize_utf8(binary) when is_binary(binary) do
    cond do
      String.valid?(binary) ->
        binary

      match?(converted when is_binary(converted), latin1_to_utf8(binary)) ->
        latin1_to_utf8(binary)

      true ->
        scrub_invalid_bytes(binary)
    end
  end

  @doc """
  Returns true when bytes are safe to show as text (valid UTF-8, no NUL, printable).
  """
  @spec printable_text?(binary()) :: boolean()
  def printable_text?(<<>>), do: true

  def printable_text?(data) when is_binary(data) do
    String.valid?(data) and :binary.match(data, <<0>>) == :nomatch and String.printable?(data)
  end

  @doc """
  Returns true when a binary should be treated as opaque octet data rather than
  character text (invalid UTF-8, embedded NUL, or non-printable control bytes).
  """
  @spec opaque_binary?(term()) :: boolean()
  def opaque_binary?(data) when is_binary(data), do: not printable_text?(data)
  def opaque_binary?(_data), do: false

  @doc """
  Sanitizes **presentation** string fields on a property row used by LiveView assigns.

  Domain binaries are preserved:
  * `raw_binary` is never UTF-8-repaired (opaque octets / MAC bytes)
  * top-level `:value` is only sanitized when it is character-string text
  * nested display `field.value` binaries are left intact (domain data; UI uses `formatted`)
  """
  @spec sanitize_property_row(map()) :: map()
  def sanitize_property_row(row) when is_map(row) do
    row
    |> Map.update(:property_name, nil, &sanitize_utf8/1)
    |> Map.update(:value_formatted, nil, &sanitize_utf8/1)
    |> Map.update(
      :value_display,
      %{kind: :scalar, formatted: "-", fields: [], items: []},
      &sanitize_display/1
    )
    |> sanitize_row_value()
    |> Map.update(:enum_options, nil, &sanitize_enum_options/1)
  end

  @doc """
  Sanitizes common user-visible string fields on BACnet object maps.
  """
  @spec sanitize_object(map() | nil) :: map() | nil
  def sanitize_object(nil), do: nil

  def sanitize_object(object) when is_map(object) do
    object
    |> Map.update(:name, nil, &sanitize_utf8/1)
    |> Map.update(:description, nil, &sanitize_utf8/1)
    |> Map.update(:type_label, nil, &sanitize_utf8/1)
    |> Map.update(:present_value_formatted, nil, &sanitize_utf8/1)
    |> Map.update(:active_priority_value_formatted, nil, &sanitize_utf8/1)
  end

  defp sanitize_display(%{} = display) do
    display
    |> Map.update!(:formatted, &sanitize_utf8/1)
    |> Map.update(:fields, [], &sanitize_fields/1)
    |> Map.update(:items, [], &sanitize_items/1)
  end

  defp sanitize_display(other), do: other

  defp sanitize_fields(fields) when is_list(fields), do: Enum.map(fields, &sanitize_field/1)
  defp sanitize_fields(_fields), do: []

  defp sanitize_items(items) when is_list(items), do: Enum.map(items, &sanitize_item/1)
  defp sanitize_items(_items), do: []

  defp sanitize_field(%{} = field) do
    field
    |> Map.update(:label, nil, &sanitize_utf8/1)
    |> Map.update!(:formatted, &sanitize_utf8/1)
    # Nested field values are domain data (e.g. RecipientAddress.address MAC octets).
    # Never Latin-1-expand them — only presentation strings above are sanitized.
    |> Map.update(:fields, [], &sanitize_fields/1)
    |> Map.update(:items, [], &sanitize_items/1)
  end

  defp sanitize_field(field), do: field

  defp sanitize_item(%{} = item), do: sanitize_field(item)
  defp sanitize_item(item), do: item

  defp sanitize_row_value(row) when is_map(row) do
    case Map.get(row, :value) do
      value when is_binary(value) ->
        if sanitize_top_level_binary?(row) do
          Map.put(row, :value, sanitize_utf8(value))
        else
          row
        end

      %{__struct__: struct_mod, type: :character_string, value: inner} = encoding
      when is_binary(inner) ->
        if encoding_module?(struct_mod) do
          Map.put(row, :value, %{encoding | value: sanitize_utf8(inner)})
        else
          row
        end

      _other ->
        row
    end
  end

  defp sanitize_top_level_binary?(row) do
    cond do
      octet_string_row?(row) -> false
      character_string_row?(row) -> true
      # Untyped binary presented as character text (fallback typing).
      Map.get(row, :type) == "CHARACTER STRING" -> true
      Map.get(row, :string_value?) == true and Map.get(row, :type) != "OCTET STRING" -> true
      true -> false
    end
  end

  defp character_string_row?(row) do
    bac_type = Map.get(row, :bac_type)
    type_label = Map.get(row, :type)

    bac_type in [:string, :character_string] or type_label == "CHARACTER STRING"
  end

  defp octet_string_row?(row) do
    bac_type = Map.get(row, :bac_type)
    type_label = Map.get(row, :type)

    bac_type == :octet_string or type_label == "OCTET STRING"
  end

  defp encoding_module?(mod) do
    mod == BACnet.Protocol.ApplicationTags.Encoding
  end

  defp latin1_to_utf8(binary) do
    case :unicode.characters_to_binary(binary, :latin1, :utf8) do
      converted when is_binary(converted) -> converted
      _binary -> nil
    end
  end

  defp sanitize_enum_options(nil), do: nil

  defp sanitize_enum_options(options) when is_list(options) do
    Enum.map(options, fn
      %{label: label} = opt -> Map.put(opt, :label, sanitize_utf8(label))
      opt -> opt
    end)
  end

  defp sanitize_enum_options(options), do: options

  defp scrub_invalid_bytes(binary) do
    for <<byte <- binary>>, into: <<>> do
      if byte < 128, do: <<byte>>, else: @replacement
    end
  end
end
