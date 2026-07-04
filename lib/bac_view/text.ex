defmodule BacView.Text do
  @moduledoc false

  @replacement "\uFFFD"

  @doc """
  Ensures a binary is valid UTF-8 for JSON/LiveView serialization.

  Tries a Latin-1 reinterpretation first (common for BACnet CharacterStrings),
  then replaces remaining invalid bytes.
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
  Sanitizes string fields in a property row used by LiveView assigns.
  """
  @spec sanitize_property_row(map()) :: map()
  def sanitize_property_row(row) when is_map(row) do
    row
    |> Map.update(:property_name, nil, &sanitize_utf8/1)
    |> Map.update(:value_formatted, nil, &sanitize_utf8/1)
    |> Map.update(
      :value_display,
      %{kind: :scalar, formatted: "—", fields: [], items: []},
      &sanitize_display/1
    )
    |> Map.update(:value, nil, &sanitize_property_value/1)
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
    |> Map.update(:fields, [], &sanitize_fields/1)
    |> Map.update(:items, [], &sanitize_items/1)
  end

  defp sanitize_field(field), do: field

  defp sanitize_item(%{} = item), do: sanitize_field(item)
  defp sanitize_item(item), do: item

  defp sanitize_property_value(value) when is_binary(value), do: sanitize_utf8(value)
  defp sanitize_property_value(value), do: value

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
