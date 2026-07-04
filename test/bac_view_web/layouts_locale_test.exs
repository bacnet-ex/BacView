defmodule BacViewWeb.LayoutsLocaleTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import BacViewWeb.Layouts

  test "app layout renders help label in english" do
    assigns = %{
      flash: %{},
      locale: "en",
      locale_version: 1,
      show_shortcuts: false,
      shortcuts_context: :dashboard,
      inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "body" end}],
      topbar_end: []
    }

    html =
      assigns
      |> app()
      |> rendered_to_string()

    assert html =~ "Help"
    refute html =~ ">Hilfe<"
  end
end
