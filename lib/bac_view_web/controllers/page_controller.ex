defmodule BacViewWeb.PageController do
  use BacViewWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
