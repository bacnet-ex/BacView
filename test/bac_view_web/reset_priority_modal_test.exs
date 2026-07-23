defmodule BacViewWeb.ResetPriorityModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.ResetPriorityModal

  defp render_modal(modal, assigns \\ %{}) do
    render_component(
      &ResetPriorityModal.modal/1,
      Map.merge(
        %{
          modal: modal,
          busy: false,
          locale: "de",
          locale_version: 0
        },
        assigns
      )
    )
  end

  test "confirm mode shows fixed priority and no priority select" do
    html =
      render_modal(%{
        mode: :confirm,
        priority: 8,
        commandable_count: 3,
        skipped_count: 1
      })

    assert html =~ ~s(id="reset-priority-modal")
    assert html =~ ~s(id="reset-priority-form")
    assert html =~ ~s(phx-submit="confirm_reset_selected_priority")
    assert html =~ "Priorität 8 zurücksetzen"
    assert html =~ "3 commandable"
    assert html =~ "1 ausgewählte"
    refute html =~ ~s(id="reset-priority-select")
    assert html =~ ~s(id="reset-priority-confirm")
  end

  test "choose mode shows priority select prefilled with session priority" do
    html =
      render_modal(%{
        mode: :choose,
        priority: 12,
        commandable_count: 2,
        skipped_count: 0
      })

    assert html =~ "Priorität wählen"
    assert html =~ ~s(id="reset-priority-select")
    assert html =~ ~s(name="priority")
    assert html =~ ~s(value="12" selected)
    assert html =~ "Zurücksetzen"
  end

  test "disables confirm when busy or no commandable objects" do
    busy =
      render_modal(
        %{mode: :confirm, priority: 8, commandable_count: 1, skipped_count: 0},
        %{busy: true}
      )

    assert busy =~ ~r/id="reset-priority-confirm"[^>]*disabled/

    empty =
      render_modal(%{
        mode: :confirm,
        priority: 8,
        commandable_count: 0,
        skipped_count: 2
      })

    assert empty =~ ~r/id="reset-priority-confirm"[^>]*disabled/
  end
end
