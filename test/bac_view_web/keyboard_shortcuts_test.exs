defmodule BacViewWeb.KeyboardShortcutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.KeyboardShortcuts

  test "device help lists list-specific subscription shortcuts in english" do
    html =
      render_component(&KeyboardShortcuts.keyboard_shortcuts/1,
        show: true,
        context: :device,
        locale: "en",
        locale_version: 1
      )

    assert html =~ "List actions"
    assert html =~ "Object list"
    assert html =~ "Subscribe COV (selection)"
    assert html =~ "Cancel COV (selection)"
    assert html =~ "Subscribe all present values"
    assert html =~ "Resubscribe (selection)"
    assert html =~ "Cancel selected"
    assert html =~ "Cancel all"
    assert html =~ "Enroll recipient list"
    assert html =~ "Remove recipient list"
    assert html =~ "Fetch events"
    assert html =~ ~s(<kbd class="bac-kbd">Shift + c</kbd>)
    assert html =~ ~s(<kbd class="bac-kbd">Shift + u</kbd>)
    assert html =~ ~s(<kbd class="bac-kbd">e</kbd>)
  end

  test "dashboard help omits device list shortcuts" do
    html =
      render_component(&KeyboardShortcuts.keyboard_shortcuts/1,
        show: true,
        context: :dashboard,
        locale: "en",
        locale_version: 1
      )

    refute html =~ "List actions"
    refute html =~ "Subscribe COV (selection)"
  end
end
