defmodule BacView.BACnet.Protocol.BinaryPV do
  @moduledoc false

  alias BacView.Text

  @binary_types [
    :binary_input,
    :binary_output,
    :binary_value,
    :binary_lighting_output
  ]

  @value_properties [:present_value, :relinquish_default]

  @spec value_properties() :: [atom()]
  def value_properties(), do: @value_properties

  @spec value_property?(atom() | term()) :: boolean()
  def value_property?(property) when property in @value_properties, do: true
  def value_property?(_property), do: false

  @spec binary_object_type?(atom()) :: boolean()
  def binary_object_type?(type) when type in @binary_types, do: true
  def binary_object_type?(_type), do: false

  @spec binary_object?(map() | nil) :: boolean()
  def binary_object?(%{type: type}), do: binary_object_type?(type)
  def binary_object?(_object), do: false

  @spec has_state_texts?(map() | nil) :: boolean()
  def has_state_texts?(object) when is_map(object) do
    not is_nil(state_text(object, :inactive_text)) or
      not is_nil(state_text(object, :active_text))
  end

  def has_state_texts?(_object), do: false

  @spec inactive_text(map()) :: String.t() | nil
  def inactive_text(object) when is_map(object), do: state_text(object, :inactive_text)

  @spec active_text(map()) :: String.t() | nil
  def active_text(object) when is_map(object), do: state_text(object, :active_text)

  @spec normalize_text(term()) :: String.t() | nil
  def normalize_text(text) when is_binary(text) do
    trimmed = text |> Text.sanitize_utf8() |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  def normalize_text(_text), do: nil

  @spec object_fields(map()) :: map()
  def object_fields(obj) when is_map(obj) do
    if binary_object?(obj) or Map.has_key?(obj, :inactive_text) or Map.has_key?(obj, :active_text) do
      %{
        inactive_text: inactive_text(obj),
        active_text: active_text(obj)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    else
      %{}
    end
  end

  @doc """
  Formats a binary present-value style value using `inactive_text` / `active_text`
  when available. Falls back to `"false"` / `"true"` for boolean-like values on
  binary objects. Returns `nil` when the value is not a binary PV (caller should
  use generic formatting).
  """
  @spec format_value(term(), map() | nil) :: String.t() | nil
  def format_value(_value, nil), do: nil

  def format_value(value, object) when is_map(object) do
    if binary_object?(object) do
      case normalize_value(value) do
        nil ->
          nil

        bool ->
          case text_for_value(object, bool) do
            nil -> if(bool, do: "true", else: "false")
            text -> text
          end
      end
    else
      nil
    end
  end

  @spec text_for_value(map(), term()) :: String.t() | nil
  def text_for_value(object, value) when is_map(object) do
    case normalize_value(value) do
      false -> inactive_text(object)
      true -> active_text(object)
      nil -> nil
    end
  end

  @doc """
  Dropdown options for writing a binary present value.

  Labels use `inactive_text` / `active_text` when present, otherwise `"false"` / `"true"`.
  """
  @spec state_options(map()) :: [%{value: boolean(), label: String.t()}]
  def state_options(object) when is_map(object) do
    if binary_object?(object) do
      [
        %{value: true, label: option_label(object, true)},
        %{value: false, label: option_label(object, false)}
      ]
    else
      []
    end
  end

  @spec normalize_value(term()) :: boolean() | nil
  def normalize_value(value) when is_boolean(value), do: value
  def normalize_value(0), do: false
  def normalize_value(1), do: true

  def normalize_value(value) when is_float(value) do
    case trunc(value) do
      0 -> false
      1 -> true
      _other -> nil
    end
  end

  def normalize_value(_value), do: nil

  defp option_label(object, bool) do
    case text_for_value(object, bool) do
      nil -> if(bool, do: "true", else: "false")
      text -> text
    end
  end

  defp state_text(object, key) do
    object
    |> Map.get(key)
    |> normalize_text()
  end
end
