defmodule BacViewWeb.AppFooterTest do
  use BacViewWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias BacView.BuildInfo
  alias BacView.Test.BacnetEtsLock

  # DashboardLive lists devices from :bacview_devices. Hold the ETS lock so
  # concurrent tests cannot leave partial device maps visible mid-mount.
  @tables [
    {:bacview_devices, [:named_table, :set, :public, read_concurrency: true]}
  ]

  test "dashboard footer shows version and build time", %{conn: conn} do
    BacnetEtsLock.with_tables(@tables, fn ->
      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert has_element?(view, "#app-footer")
      assert has_element?(view, "#app-footer-version")
      assert has_element?(view, "#app-footer-build")
      assert html =~ "BacView v#{BuildInfo.version_label()}"
      assert html =~ BuildInfo.built_at()
    end)
  end
end
