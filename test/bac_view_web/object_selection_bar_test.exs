defmodule BacViewWeb.ObjectSelectionBarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.ObjectSelectionBar

  test "renders COV and priority-reset actions for selected objects" do
    html =
      render_component(&ObjectSelectionBar.selection_bar/1,
        count: 3,
        write_priority: 8,
        bulk_resetting: false,
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~s/id="object-selection-bar"/
    assert html =~ ~s/id="reset-selected-priority"/
    assert html =~ ~s/id="reset-selected-priority-other"/
    assert html =~ "phx-click=\"open_reset_priority_confirm\""
    assert html =~ "phx-click=\"open_reset_priority_choose\""
    assert html =~ "phx-click=\"subscribe_selected_cov\""
    assert html =~ "Priorität 8 zurücksetzen"
    assert html =~ "Andere Priorität"
  end

  test "labels primary reset with session write priority" do
    html =
      render_component(&ObjectSelectionBar.selection_bar/1,
        count: 1,
        write_priority: 5,
        bulk_resetting: false,
        locale: "de",
        locale_version: 0
      )

    assert html =~ "Priorität 5 zurücksetzen"
  end

  test "disables actions while bulk resetting" do
    html =
      render_component(&ObjectSelectionBar.selection_bar/1,
        count: 2,
        write_priority: 8,
        bulk_resetting: true,
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~r/id="reset-selected-priority"[^>]*disabled/
    assert html =~ ~r/id="reset-selected-priority-other"[^>]*disabled/
  end
end
