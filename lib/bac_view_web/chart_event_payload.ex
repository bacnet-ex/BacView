defmodule BacViewWeb.ChartEventPayload do
  @moduledoc false

  @spec series_payload([map()]) :: [map()]
  def series_payload(series) when is_list(series) do
    Enum.map(series, &series_entry_payload/1)
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
