defmodule BacView.BACnet.Protocol.TrendLogChart do
  @moduledoc false

  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.DeviceObjectPropertyRef
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.TrendLogReader
  alias BacView.Timezone

  @spec naive_to_unix_ms(NaiveDateTime.t()) :: integer()
  defdelegate naive_to_unix_ms(naive), to: Timezone

  @spec unix_ms_to_naive(integer()) :: NaiveDateTime.t()
  defdelegate unix_ms_to_naive(ms), to: Timezone

  @spec range_from_records([map()]) :: {NaiveDateTime.t(), NaiveDateTime.t()}
  def range_from_records(records) when is_list(records) do
    records
    |> Enum.map(&TrendLogReader.record_timestamp/1)
    |> Enum.flat_map(fn
      {:ok, at} -> [at]
      _records -> []
    end)
    |> case do
      [] ->
        now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
        {now, now}

      timestamps ->
        sorted = Enum.sort(timestamps, NaiveDateTime)
        {List.first(sorted), List.last(sorted)}
    end
  end

  @spec to_form_value(NaiveDateTime.t()) :: String.t()
  def to_form_value(%NaiveDateTime{} = dt) do
    dt
    |> NaiveDateTime.to_string()
    |> String.slice(0, 16)
    |> String.replace(" ", "T")
  end

  @spec parse_form_value(String.t()) :: {:ok, NaiveDateTime.t()} | :error
  def parse_form_value(value) when is_binary(value) do
    value =
      value
      |> String.trim()
      |> String.replace("T", " ")

    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, naive} ->
        {:ok, naive}

      _value ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> {:ok, naive}
          _value -> :error
        end
    end
  end

  def parse_form_value(_value), do: :error

  @spec build([map()], ObjectIdentifier.t(), keyword()) :: map()
  def build(records, %ObjectIdentifier{type: type}, opts) when is_list(records) do
    refs = Keyword.get(opts, :property_refs, [])
    objects = Keyword.get(opts, :device_objects, [])
    units = Keyword.get(opts, :units) || Keyword.get(opts, :object_units)
    start_dt = Keyword.get(opts, :start_dt)
    end_dt = Keyword.get(opts, :end_dt)

    series_defs = series_definitions(type, refs, objects, units)

    {series, markers} =
      Enum.reduce(records, {init_series(series_defs), []}, fn record, {series_acc, markers_acc} ->
        accumulate_record(record, series_defs, series_acc, markers_acc)
      end)

    series =
      series
      |> Enum.map(fn {id, data} ->
        data
        |> Map.put(:points, Enum.sort_by(data.points, & &1.t))
        |> Map.put(:id, id)
      end)
      |> Enum.filter(fn %{points: points} -> points != [] end)

    scales = build_scales(series)

    series = Enum.map(series, &Map.drop(&1, [:enum_object, :enum_ticks]))

    %{
      series: series,
      scales: scales,
      markers: Enum.sort_by(markers, & &1.t),
      range: %{
        start: start_dt && naive_to_unix_ms(start_dt),
        end: end_dt && naive_to_unix_ms(end_dt)
      }
    }
  end

  defp init_series(series_defs) do
    Map.new(series_defs, fn defn ->
      {defn.id,
       %{
         id: defn.id,
         label: defn.label,
         unit: defn.unit,
         unit_label: defn.unit_label,
         scale_id: defn.scale_id,
         points: [],
         enum_object: Map.get(defn, :enum_object),
         enum_ticks: Map.get(defn, :enum_ticks),
         paths: Map.get(defn, :paths)
       }}
    end)
  end

  defp series_definitions(:trend_log, [ref | _trend_log], objects, units) do
    [series_def(0, ref, units, objects)]
  end

  defp series_definitions(:trend_log, [], _objects, units) do
    [series_def(0, nil, units, [])]
  end

  defp series_definitions(:trend_log_multiple, refs, objects, _units) when is_list(refs) do
    refs
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.map(fn {ref, index} ->
      unit = ref_unit(ref, objects)
      series_def(index, ref, unit, objects)
    end)
  end

  defp series_definitions(:trend_log_multiple, _trend_log, _series_definitions2, _objects), do: []

  defp series_def(index, ref, unit, objects) do
    object = ref_object(ref, objects)
    property = ref_property(ref)
    enum_chart? = MultistateState.enum_chart?(object, property)
    resolved_unit = normalize_unit(unit || ref_unit(ref, objects))

    scale_id =
      if enum_chart?, do: enum_scale_id(ref, index), else: scale_id_for(resolved_unit)

    base = %{
      id: "s#{index}",
      label: ref_label(ref, objects, index),
      unit: resolved_unit,
      unit_label: unit_label(resolved_unit),
      scale_id: scale_id,
      enum_object: if(enum_chart?, do: object, else: nil),
      enum_ticks: if(enum_chart?, do: MultistateState.enum_ticks(object), else: nil)
    }

    if enum_chart?, do: Map.put(base, :paths, "stepped"), else: base
  end

  defp accumulate_record(
         %{type: :log_record, timestamp: timestamp, datum: datum},
         _series_defs,
         series_acc,
         markers_acc
       ) do
    with {:ok, at} <- datetime_to_ms(timestamp),
         {:ok, value} <- TrendLogReader.numeric_value(datum),
         series when not is_nil(series) <- Map.get(series_acc, "s0") do
      point = build_chart_point(at, value, Map.get(series, :enum_object))

      {Map.update!(series_acc, "s0", &Map.update!(&1, :points, fn pts -> [point | pts] end)),
       maybe_marker(markers_acc, at, datum)}
    else
      {:ok, at} ->
        {series_acc, maybe_marker(markers_acc, at, datum)}

      _record ->
        {series_acc, markers_acc}
    end
  end

  defp accumulate_record(
         %{type: :log_multiple_record, timestamp: timestamp, data: data},
         _series_defs,
         series_acc,
         markers_acc
       )
       when is_list(data) do
    case datetime_to_ms(timestamp) do
      {:ok, at} ->
        {updated_series, updated_markers} =
          data
          |> Enum.with_index()
          |> Enum.reduce({series_acc, markers_acc}, fn {datum, index}, {s_acc, m_acc} ->
            id = "s#{index}"

            case {Map.get(s_acc, id), TrendLogReader.numeric_value(datum)} do
              {series, {:ok, value}} when not is_nil(series) ->
                point = build_chart_point(at, value, Map.get(series, :enum_object))

                {Map.update!(s_acc, id, &Map.update!(&1, :points, fn pts -> [point | pts] end)),
                 m_acc}

              _record ->
                {s_acc, maybe_marker(m_acc, at, datum)}
            end
          end)

        marker =
          if Enum.all?(data, &(TrendLogReader.marker_kind(&1) != nil)),
            do: maybe_marker(updated_markers, at, List.first(data)),
            else: updated_markers

        {updated_series, marker}

      _record ->
        {series_acc, markers_acc}
    end
  end

  defp accumulate_record(_record, _series_defs, series_acc, markers_acc),
    do: {series_acc, markers_acc}

  defp maybe_marker(markers, at, datum) do
    case TrendLogReader.marker_kind(datum) do
      nil ->
        markers

      kind ->
        [
          %{
            t: at,
            kind: kind,
            label: marker_label(kind)
          }
          | markers
        ]
    end
  end

  defp marker_label(:buffer_purged), do: "Buffer purged"
  defp marker_label(:log_disabled), do: "Log disabled"
  defp marker_label(:log_interrupted), do: "Log interrupted"
  defp marker_label(:log_status), do: "Log status"
  defp marker_label(:read_error), do: "Read error"
  defp marker_label(:time_change), do: "Time change"

  defp build_scales(series) do
    series
    |> Enum.map(& &1.scale_id)
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.map(fn {scale_id, index} ->
      sample = Enum.find(series, &(&1.scale_id == scale_id))
      scale_entry(scale_id, sample, index)
    end)
  end

  defp scale_entry(scale_id, sample, index) do
    side = if(rem(index, 2) == 0, do: "left", else: "right")

    case sample && Map.get(sample, :enum_ticks) do
      ticks when is_list(ticks) and ticks != [] ->
        %{
          id: scale_id,
          label: "",
          side: side,
          kind: "enum",
          ticks: ticks
        }

      _ticks ->
        %{
          id: scale_id,
          label: scale_label(sample),
          side: side
        }
    end
  end

  defp build_chart_point(at, value, enum_object) when is_map(enum_object) do
    v = trunc(value)

    case MultistateState.format_present_value(v, enum_object) do
      label when is_binary(label) and label != "" -> %{t: at, v: v, label: label}
      _label -> %{t: at, v: v}
    end
  end

  defp build_chart_point(at, value, _enum_object), do: %{t: at, v: value}

  defp enum_scale_id(
         %DeviceObjectPropertyRef{
           object_identifier: %ObjectIdentifier{type: type, instance: instance}
         },
         _index
       ),
       do: "states-#{type}-#{instance}"

  defp enum_scale_id(_ref, index), do: "states-s#{index}"

  defp ref_object(
         %DeviceObjectPropertyRef{
           object_identifier: %ObjectIdentifier{type: type, instance: instance}
         },
         objects
       )
       when is_list(objects) do
    Enum.find(objects, &(&1.type == type and &1.instance == instance))
  end

  defp ref_object(_ref, _objects), do: nil

  defp ref_property(%DeviceObjectPropertyRef{property_identifier: property}), do: property
  defp ref_property(_ref), do: :present_value

  defp scale_id_for(nil), do: "raw"
  defp scale_id_for(unit) when is_atom(unit), do: Atom.to_string(unit)

  defp unit_label(nil), do: ""

  defp unit_label(unit) when is_atom(unit), do: EngineeringUnits.symbol(unit)

  defp scale_label(%{unit_label: unit_label}) when is_binary(unit_label) and unit_label != "",
    do: unit_label

  defp scale_label(_sample), do: ""

  defp normalize_unit(nil), do: nil
  defp normalize_unit(unit) when is_atom(unit), do: unit
  defp normalize_unit(_nil), do: nil

  defp ref_label(%DeviceObjectPropertyRef{} = ref, objects, _index), do: ref_label(ref, objects)
  defp ref_label(nil, _objects, 0), do: "Value"
  defp ref_label(_ref_label, _objects, index), do: "Series #{index + 1}"

  defp ref_label(%DeviceObjectPropertyRef{} = ref, objects) do
    obj = ref.object_identifier

    prop =
      ref.property_identifier
      |> Atom.to_string()
      |> String.replace("_", " ")

    base = "#{obj.type}:#{obj.instance} #{prop}"

    case ref_description(ref, objects) do
      nil -> base
      description -> "#{description} (#{base})"
    end
  end

  defp ref_description(
         %DeviceObjectPropertyRef{
           object_identifier: %ObjectIdentifier{type: type, instance: instance}
         },
         objects
       )
       when is_list(objects) do
    Enum.find_value(objects, fn obj ->
      if obj.type == type and obj.instance == instance do
        case Map.get(obj, :description) do
          desc when is_binary(desc) ->
            case String.trim(desc) do
              "" -> nil
              trimmed -> trimmed
            end

          _ref_description ->
            nil
        end
      end
    end)
  end

  defp ref_description(_ref_description, _ref_description2), do: nil

  defp ref_unit(
         %DeviceObjectPropertyRef{
           object_identifier: %ObjectIdentifier{type: type, instance: instance}
         },
         objects
       )
       when is_list(objects) do
    Enum.find_value(objects, fn obj ->
      if obj.type == type and obj.instance == instance, do: Map.get(obj, :units)
    end)
  end

  defp ref_unit(_ref_unit, _ref_unit2), do: nil

  @doc false
  @spec property_refs_from_properties([map()]) :: [DeviceObjectPropertyRef.t()]
  def property_refs_from_properties(properties) when is_list(properties) do
    case Enum.find(properties, &(&1.property == :log_device_object_property)) do
      %{value: value} -> unwrap_refs(value)
      _properties -> []
    end
  end

  def property_refs_from_properties(_properties), do: []

  defp unwrap_refs(%DeviceObjectPropertyRef{} = ref), do: [ref]

  defp unwrap_refs(%BACnetArray{} = array) do
    array
    |> BACnetArray.to_list()
    |> Enum.flat_map(&unwrap_refs/1)
  end

  defp unwrap_refs(%{items: items}) when is_list(items), do: Enum.flat_map(items, &unwrap_refs/1)

  defp unwrap_refs(items) when is_list(items), do: Enum.flat_map(items, &unwrap_refs/1)

  defp unwrap_refs(_ref), do: []

  defp datetime_to_ms(%BACnetDateTime{} = dt) do
    case BACnetDateTime.to_naive_datetime(dt) do
      {:ok, naive} -> {:ok, naive_to_unix_ms(naive)}
      _dt -> :error
    end
  end
end
