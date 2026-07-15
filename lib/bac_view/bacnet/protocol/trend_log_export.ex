defmodule BacView.BACnet.Protocol.TrendLogExport do
  @moduledoc false

  alias BacView.BACnet.Protocol.TrendLogChart

  @csv_separator ";"

  @spec to_csv(map()) :: String.t()
  def to_csv(%{series: series}) when is_list(series) do
    series = Enum.filter(series, &(&1.points != []))
    timestamps = collect_timestamps(series)

    header =
      (["timestamp"] ++ Enum.map(series, &series_header/1))
      |> Enum.join(@csv_separator)
      |> Kernel.<>("\n")

    rows =
      Enum.map(timestamps, fn t ->
        cells =
          [format_timestamp(t)] ++
            Enum.map(series, fn %{points: points} ->
              case Enum.find(points, &(&1.t == t)) do
                %{label: label} when is_binary(label) and label != "" ->
                  csv_cell(label)

                %{v: value} ->
                  csv_cell(value)

                _series ->
                  ""
              end
            end)

        Enum.join(cells, @csv_separator)
      end)

    header <> Enum.join(rows, "\n")
  end

  def to_csv(_series), do: "timestamp\n"

  @spec to_json(map(), keyword()) :: String.t()
  def to_json(data, opts \\ [])

  def to_json(%{series: series} = data, opts) when is_list(series) do
    series = Enum.filter(series, &(&1.points != []))

    payload = %{
      object: object_meta(opts),
      range: export_range(opts, data),
      series: Enum.map(series, &series_to_json/1),
      markers: Enum.map(Map.get(data, :markers, []), &marker_to_json/1)
    }

    Jason.encode!(payload, pretty: true)
  end

  def to_json(_data, opts) do
    Jason.encode!(%{object: object_meta(opts), series: [], markers: []}, pretty: true)
  end

  @spec filename(atom(), integer(), NaiveDateTime.t() | nil, NaiveDateTime.t() | nil, String.t()) ::
          String.t()
  def filename(type, instance, start_dt, end_dt, ext \\ "csv") do
    start_part = filename_part(start_dt, "start")
    end_part = filename_part(end_dt, "end")
    "bacview-trend-#{type}-#{instance}-#{start_part}-#{end_part}.#{ext}"
  end

  defp collect_timestamps(series) do
    series
    |> Enum.flat_map(fn %{points: points} -> Enum.map(points, & &1.t) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp series_header(%{label: label, unit_label: unit_label}) do
    csv_cell(series_header_label(label, unit_label))
  end

  defp series_header_label(label, unit_label)
       when is_binary(unit_label) and unit_label not in ["", "-"],
       do: "#{label} (#{unit_label})"

  defp series_header_label(label, _unit_label), do: label

  defp format_timestamp(ms) when is_integer(ms) do
    ms
    |> TrendLogChart.unix_ms_to_naive()
    |> NaiveDateTime.to_string()
  end

  defp filename_part(%NaiveDateTime{} = dt, _fallback) do
    dt
    |> NaiveDateTime.to_string()
    |> String.replace([" ", ":"], "-")
  end

  defp filename_part(_fallback, fallback), do: fallback

  defp series_to_json(%{label: label, unit_label: unit_label, points: points} = series) do
    %{
      id: Map.get(series, :id),
      label: label,
      unit_label: unit_label,
      scale_id: Map.get(series, :scale_id),
      points: Enum.map(points, &point_to_json/1)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp point_to_json(%{t: t, v: v} = point) do
    base = %{timestamp: format_timestamp(t), value: json_value(v)}

    case Map.get(point, :label) do
      label when is_binary(label) and label != "" -> Map.put(base, :label, label)
      _label -> base
    end
  end

  defp marker_to_json(%{t: t, kind: kind, label: label}) do
    %{timestamp: format_timestamp(t), kind: kind, label: label}
  end

  defp export_range(opts, data) do
    range = Map.get(data, :range, %{})

    %{
      start:
        format_range_dt(Keyword.get(opts, :start_dt)) || format_range_ms(Map.get(range, :start)),
      end: format_range_dt(Keyword.get(opts, :end_dt)) || format_range_ms(Map.get(range, :end))
    }
  end

  defp format_range_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_string(dt)
  defp format_range_dt(_format_range_dt), do: nil

  defp format_range_ms(ms) when is_integer(ms), do: format_timestamp(ms)
  defp format_range_ms(_ms), do: nil

  defp object_meta(opts) do
    case Keyword.get(opts, :object) do
      %{type: type, instance: instance} = object ->
        %{
          type: type,
          instance: instance,
          name: Map.get(object, :name)
        }

      _opts ->
        nil
    end
  end

  defp json_value(value) when is_float(value), do: value
  defp json_value(value) when is_integer(value), do: value
  defp json_value(value) when is_boolean(value), do: value
  defp json_value(value) when is_binary(value), do: value
  defp json_value(value), do: to_string(value)

  defp csv_cell(nil), do: ""
  defp csv_cell(value) when is_binary(value), do: "\"#{String.replace(value, "\"", "\"\"")}\""
  defp csv_cell(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 6)
  defp csv_cell(value) when is_integer(value), do: Integer.to_string(value)
  defp csv_cell(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp csv_cell(value), do: to_string(value)
end
