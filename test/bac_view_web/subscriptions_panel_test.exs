defmodule BacViewWeb.SubscriptionsPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BacViewWeb.SubscriptionsPanel

  test "renders diagram button only for trendable subscriptions" do
    trendable = %{
      device_id: 1,
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      property: :present_value,
      last_value: 21.5,
      last_value_formatted: "21.5",
      last_cov_at: ~U[2025-03-15 10:30:00Z],
      lifetime: 3600,
      expires_at: ~U[2025-03-15 11:30:00Z]
    }

    non_trendable = %{
      device_id: 1,
      object_id: %ObjectIdentifier{type: :characterstring_value, instance: 2},
      property: :present_value,
      last_value: "open",
      last_value_formatted: "open",
      last_cov_at: ~U[2025-03-15 10:30:00Z],
      lifetime: 3600,
      expires_at: ~U[2025-03-15 11:30:00Z]
    }

    html =
      render_component(
        &SubscriptionsPanel.subscriptions_panel/1,
        %{
          device_id: 1,
          list_opts: [],
          cov_view: "subscriptions",
          cov_view_paths: %{
            "subscriptions" => "/devices/1?tab=subscriptions",
            "notifications" => "/devices/1?tab=subscriptions&cov_view=notifications"
          },
          subscriptions: [trendable, non_trendable],
          objects: [
            %{
              type: :analog_input,
              instance: 1,
              name: "AI-1",
              description: "Raumtemperatur EG"
            }
          ],
          cov_notifications: [],
          locale: "de",
          locale_version: 0
        }
      )

    assert html =~ "Beschreibung"
    assert html =~ "AI-1"
    assert html =~ "Raumtemperatur EG"
    assert html =~ "cov-chart-open-analog_input-1-present_value"
    assert html =~ "phx-click=\"open_cov_chart_modal\""
    assert html =~ "Diagramm"
    refute html =~ "cov-chart-open-characterstring_value-2-present_value"
  end
end
