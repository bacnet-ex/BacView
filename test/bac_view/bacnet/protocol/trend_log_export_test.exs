defmodule BacView.BACnet.Protocol.TrendLogExportTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.TrendLogExport

  test "to_csv exports wide format with semicolon separator" do
    data = %{
      series: [
        %{
          label: "AI-1",
          unit_label: "°C",
          points: [%{t: 1_710_000_000_000, v: 12.5}]
        },
        %{
          label: "BI-2",
          unit_label: "—",
          points: [%{t: 1_710_000_000_000, v: 1.0}]
        }
      ]
    }

    csv = TrendLogExport.to_csv(data)

    assert String.starts_with?(csv, "timestamp;")
    assert csv =~ "AI-1 (°C)"
    assert csv =~ "BI-2 (—)"
    assert csv =~ "12.5"
  end

  test "filename includes object and range" do
    filename =
      TrendLogExport.filename(
        :trend_log,
        7,
        ~N[2025-03-15 10:00:00],
        ~N[2025-03-15 11:00:00]
      )

    assert filename =~ "trend_log-7"
    assert String.ends_with?(filename, ".csv")
  end

  test "to_json exports structured chart data" do
    data = %{
      series: [
        %{
          id: "s0",
          label: "AI-1",
          unit_label: "°C",
          scale_id: "degrees_celsius",
          points: [%{t: 1_710_000_000_000, v: 12.5}]
        }
      ],
      markers: [%{t: 1_710_000_000_000, kind: :time_change, label: "Time change"}],
      range: %{start: 1_710_000_000_000, end: 1_710_003_600_000}
    }

    json =
      TrendLogExport.to_json(data,
        object: %{type: :trend_log, instance: 7, name: "TL-7"},
        start_dt: ~N[2025-03-15 10:00:00],
        end_dt: ~N[2025-03-15 11:00:00]
      )

    decoded = Jason.decode!(json)

    assert decoded["object"]["type"] == "trend_log"
    assert decoded["object"]["instance"] == 7
    assert decoded["object"]["name"] == "TL-7"
    assert decoded["range"]["start"] == "2025-03-15 10:00:00"
    assert [series] = decoded["series"]
    assert series["label"] == "AI-1"
    assert [point] = series["points"]
    assert point["value"] == 12.5
    assert [marker] = decoded["markers"]
    assert marker["kind"] == "time_change"
  end

  test "json filename uses json extension" do
    filename =
      TrendLogExport.filename(
        :trend_log,
        7,
        ~N[2025-03-15 10:00:00],
        ~N[2025-03-15 11:00:00],
        "json"
      )

    assert String.ends_with?(filename, ".json")
  end
end
