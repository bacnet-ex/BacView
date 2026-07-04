defmodule BacViewWeb.LocaleSwitchLiveTest do
  use BacViewWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
    :ok
  end

  test "switching locale re-renders translated dashboard text", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "BACnet Netzwerk-Explorer"
    refute html =~ "BACnet Network Explorer"

    html =
      view
      |> element("button[phx-click=set_locale][phx-value-locale=en]")
      |> render_click()

    assert html =~ "BACnet Network Explorer"
    refute html =~ "BACnet Netzwerk-Explorer"
    assert html =~ "Scan network"
    assert html =~ "Filter devices"
    refute html =~ "Netzwerk scannen"
    assert has_element?(view, "button[phx-value-locale=en].bac-btn-primary")
  end
end
