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

  test "flash group renders a single connection error toast" do
    html =
      flash_group(%{flash: %{}, locale: "en", locale_version: 1})
      |> rendered_to_string()

    assert html =~ ~s(id="connection-error")
    refute html =~ ~s(id="client-error")
    refute html =~ ~s(id="server-error")
    assert html =~ "Unable to connect to server"
    assert html =~ "Attempting to reconnect"
    refute html =~ "Something went wrong!"
    refute html =~ "We can't find the internet"
  end

  test "flash group shows german reconnect subtitle for de locale" do
    html =
      flash_group(%{flash: %{}, locale: "de", locale_version: 0})
      |> rendered_to_string()

    assert html =~ "Verbindung zum Server nicht möglich"
    assert html =~ "Verbindung wird wiederhergestellt…"
    refute html =~ "Attempting to reconnect"
  end
end
