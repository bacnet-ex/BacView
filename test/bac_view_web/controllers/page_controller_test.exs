defmodule BacViewWeb.DashboardLiveTest do
  use BacViewWeb.ConnCase

  test "GET / renders dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "BacView"
  end
end
