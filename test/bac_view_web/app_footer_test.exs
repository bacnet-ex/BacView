defmodule BacViewWeb.AppFooterTest do
  use BacViewWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias BacView.BuildInfo

  test "dashboard footer shows version and build time", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = render(view)

    assert has_element?(view, "#app-footer")
    assert has_element?(view, "#app-footer-version")
    assert has_element?(view, "#app-footer-build")
    assert html =~ "BacView v#{BuildInfo.version_label()}"
    assert html =~ BuildInfo.built_at()
  end
end
