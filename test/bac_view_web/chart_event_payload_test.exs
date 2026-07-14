defmodule BacViewWeb.ChartEventPayloadTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.ChartEventPayload

  test "series_payload preserves point labels and stepped paths" do
    series = [
      %{
        id: "s0",
        label: "MSV-1",
        unit_label: "—",
        scale_id: "states",
        paths: "stepped",
        points: [
          %{t: 1_710_000_000_000, v: 1, label: "1 (Aus)"},
          %{t: 1_710_000_060_000, v: 2}
        ]
      }
    ]

    assert [payload] = ChartEventPayload.series_payload(series)
    assert payload.paths == "stepped"

    assert [first, second] = payload.points
    assert first.label == "1 (Aus)"
    refute Map.has_key?(second, :label)
  end
end
