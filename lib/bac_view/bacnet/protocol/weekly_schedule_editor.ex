defmodule BacView.BACnet.Protocol.WeeklyScheduleEditor do
  @moduledoc false

  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.DailySchedule
  alias BACnet.Protocol.DeviceObjectPropertyRef
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.TimeValue

  alias BACnet.Protocol.ApplicationTags.Encoding

  alias BACnet.Protocol.Constants

  alias BacView.BACnet.Protocol.ComplexPropertyEditor
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter

  @weekdays [
    %{index: 1, weekday: :monday, label: "Montag"},
    %{index: 2, weekday: :tuesday, label: "Dienstag"},
    %{index: 3, weekday: :wednesday, label: "Mittwoch"},
    %{index: 4, weekday: :thursday, label: "Donnerstag"},
    %{index: 5, weekday: :friday, label: "Freitag"},
    %{index: 6, weekday: :saturday, label: "Samstag"},
    %{index: 7, weekday: :sunday, label: "Sonntag"}
  ]

  @type value_kind :: :real | :boolean | :unsigned_integer | {:enumerated, atom()} | :text

  @type entry :: %{
          id: String.t(),
          time: String.t(),
          value: String.t(),
          value_kind: value_kind()
        }

  @type day_draft :: %{
          index: pos_integer(),
          weekday: atom(),
          label: String.t(),
          entries: [entry()]
        }

  @type draft :: %{days: [day_draft()]}

  @spec weekdays() :: [map()]
  def weekdays(), do: @weekdays

  @spec matches?(map(), map()) :: boolean()
  def matches?(%{property: :weekly_schedule, value: %BACnetArray{fixed_size: 7}}, %{
        type: :schedule
      }) do
    true
  end

  def matches?(_matches, _matches2), do: false

  @spec from_bacnet(BACnetArray.t()) :: draft()
  def from_bacnet(%BACnetArray{} = array) do
    days =
      Enum.map(@weekdays, fn %{index: index} = weekday ->
        daily =
          case BACnetArray.get_item(array, index) do
            {:ok, %DailySchedule{} = schedule} -> schedule
            _array -> %DailySchedule{schedule: []}
          end

        Map.put(weekday, :entries, entries_from_daily(daily, index))
      end)

    %{days: days}
  end

  @spec to_bacnet(draft(), BACnetArray.t(), value_kind()) ::
          {:ok, BACnetArray.t()} | {:error, term()}
  def to_bacnet(%{days: days}, %BACnetArray{} = template, value_kind) when length(days) == 7 do
    default = BACnetArray.get_default(template)
    base = BACnetArray.new(7, default)

    Enum.reduce_while(Enum.with_index(days, 1), {:ok, base}, fn {day, index}, {:ok, array} ->
      with {:ok, daily} <- day_to_daily(day, value_kind),
           {:ok, updated} <- BACnetArray.set_item(array, index, daily),
           :ok <- validate_daily_schedule(daily) do
        {:cont, {:ok, updated}}
      else
        {:error, _days} = err -> {:halt, err}
      end
    end)
  end

  def to_bacnet(_days, _to_bacnet2), do: {:error, {:fixed_bacnet_array_size, 7, 0}}

  @spec validate_weekly_array(BACnetArray.t()) :: :ok | {:error, term()}
  def validate_weekly_array(%BACnetArray{} = array) do
    Enum.reduce_while(1..BACnetArray.size(array), :ok, fn index, :ok ->
      case BACnetArray.get_item(array, index) do
        {:ok, %DailySchedule{} = daily} ->
          case validate_daily_schedule(daily) do
            :ok -> {:cont, :ok}
            {:error, _array} = err -> {:halt, err}
          end

        _array ->
          {:cont, :ok}
      end
    end)
  end

  @spec infer_value_kind([map()], BACnetArray.t()) :: value_kind()
  def infer_value_kind(properties, %BACnetArray{} = array) when is_list(properties) do
    cond do
      kind = kind_from_property_references(properties) ->
        kind

      kind = kind_from_property(properties, :schedule_default) ->
        kind

      kind = kind_from_weekly_schedule(array) ->
        kind

      kind = kind_from_property(properties, :present_value) ->
        kind

      true ->
        :real
    end
  end

  @spec align_entry_value_kinds(draft(), value_kind()) :: draft()
  def align_entry_value_kinds(%{days: days} = draft, inferred_kind) do
    %{draft | days: Enum.map(days, &align_day_entry_value_kinds(&1, inferred_kind))}
  end

  defp align_day_entry_value_kinds(day, inferred_kind) do
    Map.update!(day, :entries, fn entries ->
      Enum.map(entries, fn entry ->
        if remappable_entry_value_kind?(entry.value_kind, inferred_kind) do
          Map.put(entry, :value_kind, inferred_kind)
        else
          entry
        end
      end)
    end)
  end

  defp remappable_entry_value_kind?(current, inferred) when current != inferred do
    reference_driven_value_kind?(current) and reference_driven_value_kind?(inferred)
  end

  defp remappable_entry_value_kind?(_current, _inferred), do: false

  defp reference_driven_value_kind?(:real), do: true
  defp reference_driven_value_kind?(:unsigned_integer), do: true
  defp reference_driven_value_kind?({:enumerated, _real}), do: true
  defp reference_driven_value_kind?(_real), do: false

  @spec default_entry_value(value_kind()) :: String.t()
  def default_entry_value(:real), do: "0"
  def default_entry_value(:unsigned_integer), do: "1"
  def default_entry_value(:boolean), do: "false"

  def default_entry_value({:enumerated, enum_type}) do
    case PropertyEnumeration.options(enum_type) do
      [%{value: value} | _real] -> Atom.to_string(value)
      _real -> ""
    end
  end

  def default_entry_value(:text), do: ""

  @spec new_entry(value_kind(), pos_integer()) :: entry()
  def new_entry(value_kind, day_index) do
    %{
      id: "#{day_index}-#{entry_id_suffix()}",
      time: "00:00",
      value: default_entry_value(value_kind),
      value_kind: value_kind
    }
  end

  @spec apply_day_entries(day_draft(), map(), value_kind()) ::
          {:ok, day_draft()} | {:error, term()}
  def apply_day_entries(day, entries_params, value_kind) when is_map(entries_params) do
    existing = Map.new(day.entries, &{&1.id, &1})

    entries =
      entries_params
      |> normalize_entries_params()
      |> Enum.sort_by(fn {key, _day} -> String.to_integer(key) end)
      |> Enum.map(fn {_key, params} ->
        params = if is_map(params), do: params, else: %{}

        id = Map.get(params, "id", entry_id_suffix())

        %{
          id: id,
          time: Map.get(params, "time", ""),
          value: Map.get(params, "value", ""),
          value_kind: entry_value_kind(Map.get(existing, id), value_kind)
        }
      end)

    with :ok <- validate_entries(entries) do
      {:ok, Map.put(day, :entries, entries)}
    end
  end

  def apply_day_entries(day, entries_params, value_kind) when is_list(entries_params) do
    entries_params
    |> List.wrap()
    |> Enum.with_index()
    |> Map.new(fn {entry, index} -> {Integer.to_string(index), entry} end)
    |> then(&apply_day_entries(day, &1, value_kind))
  end

  def apply_day_entries(day, _day, _entries_params), do: {:ok, day}

  @spec add_entry(day_draft(), value_kind()) :: day_draft()
  def add_entry(day, value_kind) do
    entry = new_entry(value_kind, day.index)
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    Map.update!(day, :entries, &(&1 ++ [entry]))
  end

  @spec remove_entry(day_draft(), String.t()) :: day_draft()
  def remove_entry(day, entry_id) do
    Map.update!(day, :entries, fn entries ->
      Enum.reject(entries, &(&1.id == entry_id))
    end)
  end

  @spec encode_json(BACnetArray.t()) :: {:ok, String.t()} | {:error, term()}
  def encode_json(%BACnetArray{} = array), do: ComplexPropertyEditor.encode_json(array)

  @spec decode_json(String.t(), BACnetArray.t()) :: {:ok, BACnetArray.t()} | {:error, term()}
  def decode_json(json, %BACnetArray{} = template) do
    with {:ok, array} <- ComplexPropertyEditor.decode_json(json, template),
         :ok <- validate_weekly_array(array) do
      {:ok, array}
    end
  end

  @spec enum_options(value_kind()) :: [%{value: atom(), label: String.t()}] | nil
  def enum_options({:enumerated, enum_type}), do: PropertyEnumeration.options(enum_type)
  def enum_options(_enum_type), do: nil

  @spec draft_days(draft() | map()) :: [day_draft()]
  def draft_days(draft) when is_map(draft) do
    case draft do
      %{days: days} when is_list(days) -> days
      %{"days" => days} when is_list(days) -> days
      _draft -> []
    end
  end

  def draft_days(_draft), do: []

  defp entries_from_daily(%DailySchedule{schedule: schedule}, day_index) do
    schedule
    |> Enum.with_index()
    |> Enum.map(fn {%TimeValue{time: time, value: value}, entry_index} ->
      %{
        id: "#{day_index}-#{entry_index}",
        time: format_time_input(time),
        value: format_value_input(value),
        value_kind: entry_value_kind(value)
      }
    end)
  end

  defp day_to_daily(%{entries: entries}, default_value_kind) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case entry_to_time_value(entry, default_value_kind) do
        {:ok, %TimeValue{} = time_value} ->
          if TimeValue.valid?(time_value) do
            {:cont, {:ok, [time_value | acc]}}
          else
            {:halt, {:error, :invalid_schedule_primitive_value}}
          end

        {:error, _default_value_kind} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, time_values} ->
        sorted = Enum.sort_by(time_values, &time_sort_key/1)
        {:ok, %DailySchedule{schedule: sorted}}

      {:error, _default_value_kind} = err ->
        err
    end
  end

  defp entry_to_time_value(%{time: time, value: value} = entry, default_value_kind) do
    value_kind = Map.get(entry, :value_kind, default_value_kind)

    with {:ok, bacnet_time} <- parse_time(time),
         {:ok, tagged_value} <- encode_value(value, value_kind),
         {:ok, encoding} <- schedule_value_encoding(tagged_value) do
      {:ok, %TimeValue{time: bacnet_time, value: encoding}}
    end
  end

  defp validate_entries(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      value_kind = Map.get(entry, :value_kind, :real)

      with {:ok, _entries} <- parse_time(entry.time),
           :ok <- validate_value(entry.value, value_kind) do
        {:cont, :ok}
      else
        {:error, _entries} = err -> {:halt, err}
      end
    end)
  end

  defp entry_value_kind(%{value_kind: stored, id: _default} = _entry, default) do
    if remappable_entry_value_kind?(stored, default), do: default, else: stored
  end

  defp entry_value_kind(nil, default), do: default
  defp entry_value_kind(value, _default), do: entry_value_kind_from_value(value)
  defp entry_value_kind(value), do: entry_value_kind_from_value(value)

  defp entry_value_kind_from_value(value) do
    case kind_from_tagged_value(value) do
      :text -> :real
      kind -> kind
    end
  end

  defp parse_time(time) when is_binary(time) do
    trimmed = String.trim(time)

    if trimmed == "" do
      {:error, :invalid_schedule_time}
    else
      parse_time_string(trimmed)
    end
  end

  defp parse_time(_time), do: {:error, :invalid_schedule_time}

  defp parse_time_string(trimmed) do
    case String.split(trimmed, ".", parts: 2) do
      [clock, fraction] ->
        with {:ok, {h, m, s}} <- parse_clock(clock),
             {:ok, hu} <- parse_hundredth_fraction(fraction) do
          {:ok, %BACnetTime{hour: h, minute: m, second: s, hundredth: hu}}
        end

      [clock] ->
        with {:ok, {h, m, s}} <- parse_clock(clock) do
          {:ok, %BACnetTime{hour: h, minute: m, second: s, hundredth: 0}}
        end
    end
  end

  defp parse_clock(clock) do
    case String.split(clock, ":") do
      [hour, minute] ->
        with {:ok, h} <- parse_hour(hour),
             {:ok, m} <- parse_minute(minute) do
          {:ok, {h, m, 0}}
        end

      [hour, minute, second] ->
        with {:ok, h} <- parse_hour(hour),
             {:ok, m} <- parse_minute(minute),
             {:ok, s} <- parse_second(second) do
          {:ok, {h, m, s}}
        end

      _clock ->
        {:error, :invalid_schedule_time}
    end
  end

  defp parse_hour(value) do
    case Integer.parse(value) do
      {int, ""} when int in 0..23 -> {:ok, int}
      _value -> {:error, :invalid_schedule_time}
    end
  end

  defp parse_minute(value) do
    case Integer.parse(value) do
      {int, ""} when int in 0..59 -> {:ok, int}
      _value -> {:error, :invalid_schedule_time}
    end
  end

  defp parse_second(value) do
    case Integer.parse(value) do
      {int, ""} when int in 0..59 -> {:ok, int}
      _value -> {:error, :invalid_schedule_time}
    end
  end

  defp parse_hundredth_fraction(fraction) do
    case Integer.parse(fraction) do
      {value, ""} when value in 0..99 and byte_size(fraction) <= 2 ->
        {:ok, value}

      {value, ""} when byte_size(fraction) == 3 and value in 0..999 ->
        {:ok, div(value, 10)}

      _fraction ->
        {:error, :invalid_schedule_time}
    end
  end

  defp encode_value(value, value_kind) when is_binary(value) do
    trimmed = String.trim(value)

    if null_value?(trimmed) do
      {:ok, {:null, nil}}
    else
      encode_non_null_value(trimmed, value_kind)
    end
  end

  defp encode_non_null_value(trimmed, :real) do
    case Float.parse(trimmed) do
      {float, ""} -> {:ok, {:real, float}}
      _trimmed -> {:error, :invalid_schedule_value}
    end
  end

  defp encode_non_null_value(trimmed, :unsigned_integer) do
    case parse_unsigned_input(trimmed) do
      {:ok, int} -> {:ok, {:unsigned_integer, int}}
      {:error, _trimmed} -> {:error, :invalid_schedule_value}
    end
  end

  defp encode_non_null_value(trimmed, :boolean) do
    case String.downcase(trimmed) do
      "true" -> {:ok, {:boolean, true}}
      "false" -> {:ok, {:boolean, false}}
      _trimmed -> {:error, :invalid_schedule_value}
    end
  end

  defp encode_non_null_value(trimmed, {:enumerated, enum_type}) do
    case parse_enumerated_input(trimmed, enum_type) do
      {:ok, int} -> {:ok, {:enumerated, int}}
      {:error, _trimmed} -> {:error, :invalid_schedule_value}
    end
  end

  defp encode_non_null_value(trimmed, :text) do
    {:ok, {:character_string, trimmed}}
  end

  defp validate_value(value, value_kind) do
    trimmed = String.trim(value)

    if null_value?(trimmed) do
      :ok
    else
      validate_non_null_value(trimmed, value_kind)
    end
  end

  defp validate_non_null_value(trimmed, :real) do
    case Float.parse(trimmed) do
      {_trimmed, ""} -> :ok
      _trimmed -> {:error, :invalid_schedule_value}
    end
  end

  defp validate_non_null_value(trimmed, :unsigned_integer) do
    case parse_unsigned_input(trimmed) do
      {:ok, _trimmed} -> :ok
      {:error, _trimmed} -> {:error, :invalid_schedule_value}
    end
  end

  defp validate_non_null_value(trimmed, :boolean) do
    if String.downcase(trimmed) in ["true", "false"],
      do: :ok,
      else: {:error, :invalid_schedule_value}
  end

  defp validate_non_null_value(trimmed, {:enumerated, enum_type}) do
    case parse_enumerated_input(trimmed, enum_type) do
      {:ok, _trimmed} -> :ok
      {:error, _trimmed} -> {:error, :invalid_schedule_value}
    end
  end

  defp validate_non_null_value(_trimmed, :text), do: :ok

  defp parse_unsigned_input(trimmed) do
    case Integer.parse(trimmed) do
      {int, ""} when int >= 0 ->
        {:ok, int}

      _trimmed ->
        case Float.parse(trimmed) do
          {float, ""} when float >= 0 and float == trunc(float) ->
            {:ok, trunc(float)}

          _trimmed ->
            {:error, :invalid_schedule_value}
        end
    end
  end

  defp parse_enumerated_input(trimmed, enum_type) do
    case PropertyEnumeration.parse_value(trimmed, enum_type) do
      {:ok, atom} ->
        {:ok, Constants.by_name!(enum_type, atom)}

      {:error, _trimmed} ->
        case Integer.parse(trimmed) do
          {int, ""} ->
            case Constants.by_value(enum_type, int) do
              {:ok, _trimmed} -> {:ok, int}
              :error -> {:error, :invalid_schedule_value}
            end

          _trimmed ->
            {:error, :invalid_schedule_value}
        end
    end
  end

  defp schedule_value_encoding(tagged_value) do
    case Encoding.create(tagged_value) do
      {:ok, %Encoding{encoding: :primitive} = encoding} -> {:ok, encoding}
      {:ok, _tagged_value} -> {:error, :invalid_schedule_primitive_value}
      {:error, _tagged_value} -> {:error, :invalid_schedule_value}
    end
  end

  defp validate_daily_schedule(%DailySchedule{schedule: schedule}) do
    Enum.reduce_while(schedule, :ok, fn
      %TimeValue{} = time_value, :ok ->
        if schedule_time_value_valid?(time_value) do
          {:cont, :ok}
        else
          {:halt, {:error, :invalid_schedule_primitive_value}}
        end

      _validate_daily_schedule, :ok ->
        {:halt, {:error, :invalid_schedule_primitive_value}}
    end)
  end

  defp schedule_time_value_valid?(%TimeValue{time: time, value: value}) do
    case normalize_schedule_time_value(value) do
      {:ok, %Encoding{} = encoding} ->
        TimeValue.valid?(%TimeValue{time: time, value: encoding})

      _schedule_time_value_valid ->
        false
    end
  end

  defp normalize_schedule_time_value(%Encoding{} = encoding), do: {:ok, encoding}

  defp normalize_schedule_time_value({tag, value}) when is_atom(tag),
    do: Encoding.create({tag, value})

  defp normalize_schedule_time_value(_encoding), do: :error

  defp null_value?(value), do: value == "" or String.downcase(value) == "null"

  defp format_time_input(%BACnetTime{hour: hour, minute: minute, second: 0, hundredth: 0}) do
    "#{pad2(hour)}:#{pad2(minute)}"
  end

  defp format_time_input(%BACnetTime{hour: hour, minute: minute, second: second, hundredth: 0}) do
    "#{pad2(hour)}:#{pad2(minute)}:#{pad2(second)}"
  end

  defp format_time_input(%BACnetTime{
         hour: hour,
         minute: minute,
         second: second,
         hundredth: hundredth
       }) do
    "#{pad2(hour)}:#{pad2(minute)}:#{pad2(second)}.#{pad_hundredth(hundredth)}"
  end

  defp pad2(value) when is_integer(value),
    do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp pad_hundredth(value) when value < 10,
    do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp pad_hundredth(value), do: Integer.to_string(value)

  defp format_value_input({:real, value}) when is_float(value),
    do: PropertyFormatter.format_float(value)

  defp format_value_input({:real, value}) when is_integer(value), do: Integer.to_string(value)
  defp format_value_input({:boolean, value}), do: if(value, do: "true", else: "false")
  defp format_value_input({:enumerated, value}) when is_atom(value), do: Atom.to_string(value)

  defp format_value_input({:enumerated, value}) when is_integer(value),
    do: Integer.to_string(value)

  defp format_value_input({:unsigned_integer, value}) when is_integer(value),
    do: Integer.to_string(value)

  defp format_value_input({:signed_integer, value}) when is_integer(value),
    do: Integer.to_string(value)

  defp format_value_input({:null, nil}), do: ""

  defp format_value_input(%Encoding{type: :enumerated, value: value}) when is_integer(value),
    do: format_enumerated_name(value)

  defp format_value_input(%Encoding{type: :enumerated, value: value}) when is_atom(value),
    do: Atom.to_string(value)

  defp format_value_input(%Encoding{type: :unsigned_integer, value: value})
       when is_integer(value),
       do: Integer.to_string(value)

  defp format_value_input(%Encoding{type: type, value: value})
       when type in [:real, :boolean, :null],
       do: format_value_input({type, value})

  defp format_value_input(%Encoding{value: value}), do: format_value_input(value)
  defp format_value_input(value) when is_binary(value), do: value
  defp format_value_input(value), do: inspect(value, limit: 50)

  defp time_sort_key(%TimeValue{time: %BACnetTime{hour: h, minute: m, second: s, hundredth: hu}}) do
    h * 3_600_000 + m * 60_000 + s * 1_000 + hu * 10
  end

  defp kind_from_property(properties, property) do
    case Enum.find(properties, &(&1.property == property)) do
      %{value: value} -> kind_from_value(value)
      _properties -> nil
    end
  end

  defp kind_from_property_references(properties) do
    case Enum.find(properties, &(&1.property == :list_of_object_property_references)) do
      %{value: %BACnetArray{} = array} -> kind_from_referenced_objects(array)
      _properties -> nil
    end
  end

  defp kind_from_referenced_objects(%BACnetArray{} = array) do
    array
    |> array_elements()
    |> Enum.find_value(&kind_from_object_reference/1)
  end

  defp kind_from_object_reference(%DeviceObjectPropertyRef{
         object_identifier: %ObjectIdentifier{type: type}
       }) do
    kind_from_object_type(type)
  end

  defp kind_from_object_reference(_kind_from_object_reference), do: nil

  defp kind_from_object_type(type)
       when type in [:binary_input, :binary_output, :binary_value],
       do: {:enumerated, :binary_present_value}

  defp kind_from_object_type(type)
       when type in [:multi_state_input, :multi_state_output, :multi_state_value],
       do: :unsigned_integer

  defp kind_from_object_type(type)
       when type in [:analog_input, :analog_output, :analog_value],
       do: :real

  defp kind_from_object_type(:character_string_value), do: :text
  defp kind_from_object_type(_type), do: nil

  defp kind_from_weekly_schedule(%BACnetArray{} = array) do
    array
    |> array_elements()
    |> Enum.find_value(fn
      %DailySchedule{schedule: [%TimeValue{value: value} | _array]} ->
        kind_from_tagged_value(value)

      _array ->
        nil
    end)
  end

  defp kind_from_value(%Encoding{type: type, value: value}) do
    kind_from_encoding_type(type, value)
  end

  defp kind_from_value(value), do: kind_from_tagged_value(value)

  defp kind_from_encoding_type(:real, _real), do: :real
  defp kind_from_encoding_type(:boolean, _real), do: :boolean
  defp kind_from_encoding_type(:unsigned_integer, _real), do: :unsigned_integer
  defp kind_from_encoding_type(:signed_integer, _real), do: :unsigned_integer

  defp kind_from_encoding_type(:enumerated, value),
    do: {:enumerated, enum_type_for_sample(value)}

  defp kind_from_encoding_type(:null, _real), do: :text
  defp kind_from_encoding_type(_real, value), do: kind_from_tagged_value(value)

  defp kind_from_tagged_value({:real, _atom}), do: :real
  defp kind_from_tagged_value({:boolean, _atom}), do: :boolean
  defp kind_from_tagged_value({:unsigned_integer, _atom}), do: :unsigned_integer
  defp kind_from_tagged_value({:signed_integer, _atom}), do: :unsigned_integer

  defp kind_from_tagged_value({:enumerated, atom}) when is_atom(atom),
    do: {:enumerated, enum_type_for_atom(atom)}

  defp kind_from_tagged_value({:enumerated, _atom}), do: {:enumerated, :binary_present_value}
  defp kind_from_tagged_value({:null, nil}), do: :text
  defp kind_from_tagged_value(%Encoding{} = encoding), do: kind_from_value(encoding)
  defp kind_from_tagged_value(_atom), do: :text

  defp enum_type_for_sample(value), do: enum_type_for_atom(sample_enum_atom(value))

  defp sample_enum_atom({:enumerated, atom}) when is_atom(atom), do: atom

  defp sample_enum_atom(%Encoding{type: :enumerated, value: value}),
    do: sample_enum_atom(value)

  defp sample_enum_atom(int) when is_integer(int) do
    case enum_name_for_integer(int) do
      nil -> :active
      atom -> atom
    end
  end

  defp sample_enum_atom(_atom), do: :active

  defp format_enumerated_name(int) when is_integer(int) do
    case enum_name_for_integer(int) do
      nil -> Integer.to_string(int)
      atom -> Atom.to_string(atom)
    end
  end

  defp enum_name_for_integer(int) when is_integer(int) do
    Enum.find_value(
      [:binary_present_value, :event_state, :reliability, :program_state],
      fn type ->
        case Constants.by_value(type, int) do
          {:ok, name} -> name
          :error -> nil
        end
      end
    )
  end

  defp enum_type_for_atom(atom) when is_atom(atom) do
    Enum.find(
      [:binary_present_value, :event_state, :reliability, :program_state],
      fn type -> atom in enum_values(type) end
    ) || :binary_present_value
  end

  defp enum_values(type) do
    type |> PropertyEnumeration.options() |> Enum.map(& &1.value)
  end

  defp array_elements(%BACnetArray{} = array) do
    Enum.map(1..BACnetArray.size(array), fn index ->
      case BACnetArray.get_item(array, index) do
        {:ok, item} -> item
        :error -> BACnetArray.get_default(array)
      end
    end)
  end

  defp entry_id_suffix() do
    Integer.to_string(System.unique_integer([:positive]))
  end

  defp normalize_entries_params(entries) when is_map(entries) do
    if flattened_entry_params?(entries) do
      %{"0" => entries}
    else
      entries
      |> Enum.filter(fn {key, _entries} -> entry_index_key?(key) end)
      |> Map.new()
    end
  end

  defp flattened_entry_params?(entries) do
    Map.has_key?(entries, "time") or Map.has_key?(entries, "id") or Map.has_key?(entries, "value")
  end

  defp entry_index_key?(key) when is_binary(key) do
    case Integer.parse(key) do
      {_key, ""} -> true
      _key -> false
    end
  end

  defp entry_index_key?(_key), do: false
end
