defmodule BacViewWeb.SubscriptionSelectionBarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.SubscriptionSelectionBar

  test "renders resubscribe and unsubscribe actions for selected subscriptions" do
    html =
      render_component(&SubscriptionSelectionBar.selection_bar/1,
        count: 2,
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~s/id="resubscribe-selected-subscriptions"/
    assert html =~ "phx-click=\"resubscribe_selected_subscriptions\""
    assert html =~ "phx-click=\"unsubscribe_selected_subscriptions\""
    assert html =~ "Erneut abonnieren"
    assert html =~ "Ausgewählte kündigen"
  end
end
