defmodule BacViewWeb.TrendLogChartModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.TrendLogChartModal

  test "renders object description below name in chart modal" do
    html =
      render_component(&TrendLogChartModal.modal/1,
        object: %{
          type: :trend_log,
          instance: 1,
          name: "Trend 1",
          description: "Heizungsverlauf Keller"
        },
        locale: "de",
        locale_version: 0
      )

    assert html =~ "Trend 1"
    assert html =~ "Heizungsverlauf Keller"
    assert html =~ "Log-Puffer via ReadRange"
  end

  test "omits description line when object has no description" do
    html =
      render_component(&TrendLogChartModal.modal/1,
        object: %{type: :trend_log, instance: 2, name: "Trend 2", description: nil},
        locale: "de",
        locale_version: 0
      )

    assert html =~ "Trend 2"
    refute html =~ "text-sm bac-text-muted truncate"
  end
end
