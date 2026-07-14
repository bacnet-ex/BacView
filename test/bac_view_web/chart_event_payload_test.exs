defmodule BacViewWeb.ChartEventPayloadTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.ChartEventPayload

  test "series_payload preserves point labels and stepped paths" do
    series = [
      %{
        id: "s0",
        label: "MSV-1",
        unit_label: "",
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

  test "has_data? is true when any series has points" do
    assert ChartEventPayload.has_data?(%{
             series: [%{points: [%{t: 1, v: 2}]}]
           })

    refute ChartEventPayload.has_data?(%{series: [%{points: []}]})
    refute ChartEventPayload.has_data?(%{series: []})
    refute ChartEventPayload.has_data?(nil)
  end

  test "build maps series when data is present" do
    data = %{
      series: [
        %{
          id: "s0",
          label: "AI-1",
          unit_label: "°C",
          scale_id: "celsius",
          points: [%{t: 1, v: 2.5}]
        }
      ],
      scales: [%{id: "celsius"}],
      markers: [],
      range: %{start: 1, end: 2}
    }

    built = ChartEventPayload.build(data, empty_label: "empty")
    assert [payload] = built.series
    assert payload.id == "s0"
    refute Map.has_key?(built, :empty_label)
  end

  test "build returns empty series with empty_label when no points" do
    data = %{
      series: [
        %{
          id: "s0",
          label: "AI-1",
          unit_label: "°C",
          scale_id: "celsius",
          points: []
        }
      ],
      scales: [%{id: "celsius"}],
      markers: [%{t: 1}],
      range: %{start: 1, end: 2}
    }

    built =
      ChartEventPayload.build(data,
        empty_label: "Keine plottbaren COV-Meldungen im gewählten Zeitraum."
      )

    assert built.series == []
    assert built.scales == [%{id: "celsius"}]
    assert built.markers == [%{t: 1}]
    assert built.range == %{start: 1, end: 2}
    assert built.empty_label == "Keine plottbaren COV-Meldungen im gewählten Zeitraum."
  end
end
