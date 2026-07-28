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
    assert html =~ ~s/id="reset-selected-priority-menu"/
    assert html =~ ~s/id="reset-selected-priority-other"/
    assert html =~ "phx-click=\"open_reset_priority_confirm\""
    assert html =~ "phx-click=\"open_reset_priority_choose\""
    assert html =~ "phx-click=\"subscribe_selected_cov\""
    assert html =~ "Priorität 8 zurücksetzen"
    assert html =~ "Andere Priorität"
    assert html =~ "bac-btn-split-start"
    assert html =~ "bac-btn-split-end"
    assert html =~ ~s/phx-hook="DetailsOutsideClose"/
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

  test "cov_present_value_keys keeps objects with present_value and skips the rest" do
    selected =
      MapSet.new([
        {:analog_input, 1},
        {:device, 42},
        {:notification_class, 1},
        {:structured_view, 1}
      ])

    selectable = MapSet.new([{:analog_input, 1}, {:device, 42}, {:notification_class, 1}])

    objects = [
      %{type: :analog_input, instance: 1, present_value: 21.5},
      %{type: :device, instance: 42, present_value: nil},
      %{type: :notification_class, instance: 1},
      %{type: :binary_input, instance: 9, present_value: true}
    ]

    {keys, skipped} =
      ObjectSelectionBar.cov_present_value_keys(selected, selectable, objects)

    assert Enum.sort(keys) == [analog_input: 1]
    assert skipped == 2
  end

  test "cov_present_value_keys treats zero present_value as subscribable" do
    selected = MapSet.new([{:analog_value, 3}])
    selectable = selected
    objects = [%{type: :analog_value, instance: 3, present_value: 0.0}]

    assert {[{:analog_value, 3}], 0} =
             ObjectSelectionBar.cov_present_value_keys(selected, selectable, objects)
  end
end
