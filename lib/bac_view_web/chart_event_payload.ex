defmodule BacViewWeb.ChartEventPayload do
  @moduledoc false

  @spec series_payload([map()]) :: [map()]
  def series_payload(series) when is_list(series) do
    Enum.map(series, &series_entry_payload/1)
  end

  @spec has_data?(map()) :: boolean()
  def has_data?(%{series: series}) when is_list(series) do
    Enum.any?(series, fn
      %{points: points} when is_list(points) -> points != []
      _series -> false
    end)
  end

  def has_data?(_data), do: false

  @spec build(map() | term(), keyword()) :: map()
  def build(data, opts \\ [])

  def build(%{series: series} = data, opts) when is_list(series) do
    payload_series = series_payload(series)
    empty_label = Keyword.get(opts, :empty_label, "Keine Daten geladen.")

    if has_data?(data) do
      Map.put(data, :series, payload_series)
    else
      %{
        series: [],
        scales: Map.get(data, :scales, []),
        markers: Map.get(data, :markers, []),
        range: Map.get(data, :range, %{}),
        empty_label: empty_label
      }
    end
  end

  def build(_data, opts) do
    empty_label = Keyword.get(opts, :empty_label, "Keine Daten geladen.")
    %{series: [], scales: [], empty_label: empty_label}
  end

  defp series_entry_payload(
         %{id: id, label: label, unit_label: unit_label, scale_id: scale_id, points: points} =
           series
       ) do
    maybe_put(
      %{
        id: id,
        label: label,
        unit_label: unit_label,
        scale_id: scale_id,
        points: points_payload(points)
      },
      :paths,
      Map.get(series, :paths)
    )
  end

  defp points_payload(points) when is_list(points) do
    Enum.map(points, fn %{t: t, v: v} = point ->
      maybe_put(%{t: t, v: v}, :label, Map.get(point, :label))
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
