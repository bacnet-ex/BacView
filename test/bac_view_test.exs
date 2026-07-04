defmodule BacViewTest do
  use ExUnit.Case

  test "application module is defined" do
    assert Code.ensure_loaded?(BacView)
  end
end
