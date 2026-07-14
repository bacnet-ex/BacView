defmodule BacView.BACnet.Protocol.MultistateState do
  @moduledoc false

  alias BACnet.Protocol.BACnetArray
  alias BacView.Text

  @multistate_types [:multi_state_input, :multi_state_output, :multi_state_value]
  @state_value_properties [:present_value, :relinquish_default]

  @spec state_value_properties() :: [atom()]
  def state_value_properties(), do: @state_value_properties

  @spec state_value_property?(atom() | term()) :: boolean()
  def state_value_property?(property) when property in @state_value_properties, do: true
  def state_value_property?(_property), do: false

  @spec multistate_object_type?(atom()) :: boolean()
  def multistate_object_type?(type) when type in @multistate_types, do: true
  def multistate_object_type?(_type), do: false

  @spec multistate_object?(map() | nil) :: boolean()
  def multistate_object?(%{type: type}), do: multistate_object_type?(type)

  def multistate_object?(%{number_of_states: n}) when is_integer(n) and n > 0, do: true
  def multistate_object?(%{state_text: texts}) when is_list(texts) and texts != [], do: true
  def multistate_object?(_object), do: false

  @spec normalize_state_text(term()) :: [String.t()]
  def normalize_state_text(%BACnetArray{} = array),
    do: normalize_state_text(BACnetArray.to_list(array))

  def normalize_state_text(texts) when is_list(texts) do
    Enum.map(texts, fn
      text when is_binary(text) -> Text.sanitize_utf8(text) || ""
      _text -> ""
    end)
  end

  def normalize_state_text(_text), do: []

  @spec state_texts(map()) :: [String.t()]
  def state_texts(object) when is_map(object) do
    case Map.get(object, :state_text) do
      %BACnetArray{} = array -> normalize_state_text(array)
      texts when is_list(texts) -> normalize_state_text(texts)
      _texts -> []
    end
  end

  @spec number_of_states(map()) :: pos_integer() | nil
  def number_of_states(object) when is_map(object) do
    case Map.get(object, :number_of_states) do
      n when is_integer(n) and n > 0 ->
        n

      _number_of_states ->
        texts = state_texts(object)
        if texts != [], do: length(texts), else: nil
    end
  end

  @spec state_text_for_value(map(), term()) :: String.t() | nil
  def state_text_for_value(object, value) when is_map(object) do
    case normalize_state_index(value) do
      nil ->
        nil

      index ->
        case Enum.at(state_texts(object), index) do
          text when is_binary(text) ->
            trimmed = String.trim(text)
            if trimmed == "", do: nil, else: trimmed

          _text ->
            nil
        end
    end
  end

  @spec format_present_value(term(), map() | nil) :: String.t() | nil
  def format_present_value(_value, nil), do: nil

  def format_present_value(value, object) when is_map(object) do
    if multistate_object?(object) do
      base = format_state_value(value)

      case state_text_for_value(object, value) do
        nil -> base
        text -> "#{base} (#{text})"
      end
    else
      nil
    end
  end

  @spec valid_state_value?(map(), term()) :: boolean()
  def valid_state_value?(object, value) when is_map(object) do
    case number_of_states(object) do
      n when is_integer(n) and n > 0 ->
        case normalize_state_value(value) do
          state when is_integer(state) -> state in 1..n
          _other -> false
        end

      _number_of_states ->
        false
    end
  end

  def valid_state_value?(_object, _value), do: false

  @spec state_options(map()) :: [%{value: pos_integer(), label: String.t()}]
  def state_options(object) when is_map(object) do
    case number_of_states(object) do
      n when is_integer(n) and n > 0 ->
        Enum.map(1..n, fn state ->
          label =
            case state_text_for_value(object, state) do
              nil -> Integer.to_string(state)
              text -> "#{state} (#{text})"
            end

          %{value: state, label: label}
        end)

      _number_of_states ->
        []
    end
  end

  @doc """
  True when the object/property pair can be charted as a discrete multistate series.
  """
  @spec enum_chart?(map() | nil, term()) :: boolean()
  def enum_chart?(object, property) do
    multistate_object?(object) and state_value_property?(property) and state_options(object) != []
  end

  @doc """
  Chart axis ticks derived from `state_options/1` (`%{value, label}` maps).
  """
  @spec enum_ticks(map()) :: [%{value: pos_integer(), label: String.t()}]
  def enum_ticks(object) when is_map(object), do: state_options(object)

  @spec object_fields(map()) :: map()
  def object_fields(obj) when is_map(obj) do
    type = Map.get(obj, :type)

    if multistate_object_type?(type) or Map.has_key?(obj, :number_of_states) or
         Map.has_key?(obj, :state_text) do
      %{
        number_of_states: number_of_states(obj),
        state_text: state_texts(obj)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
      |> Map.new()
    else
      %{}
    end
  end

  defp format_state_value(value) do
    case normalize_state_value(value) do
      state when is_integer(state) -> Integer.to_string(state)
      _other -> to_string(value)
    end
  end

  defp normalize_state_value(value) when is_integer(value), do: value

  defp normalize_state_value(value) when is_float(value), do: trunc(value)

  defp normalize_state_value(_value), do: nil

  defp normalize_state_index(value) when is_integer(value) and value >= 1, do: value - 1

  defp normalize_state_index(value) when is_float(value) do
    value |> trunc() |> normalize_state_index()
  end

  defp normalize_state_index(_value), do: nil
end
