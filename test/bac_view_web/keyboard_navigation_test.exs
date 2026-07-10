defmodule BacViewWeb.KeyboardNavigationTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.Shortcuts

  test "digit_index maps physical digit codes" do
    assert Shortcuts.digit_index("Digit1") == 1
    assert Shortcuts.digit_index("Digit4") == 4
    assert Shortcuts.digit_index("Digit5") == nil
    assert Shortcuts.digit_index("") == nil
  end

  test "shift_pressed? reads shift flag from keydown params" do
    assert Shortcuts.shift_pressed?(%{"shift" => true})
    refute Shortcuts.shift_pressed?(%{"shift" => false})
    refute Shortcuts.shift_pressed?(%{})
  end

  test "refresh_key? matches r and R" do
    assert Shortcuts.refresh_key?("r")
    assert Shortcuts.refresh_key?("R")
    refute Shortcuts.refresh_key?("t")
  end

  test "go_up_pressed? matches physical 0 key across layouts" do
    assert Shortcuts.go_up_pressed?(%{"key" => "0", "code" => "Digit0", "shift" => false})
    assert Shortcuts.go_up_pressed?(%{"key" => "0", "code" => "", "shift" => false})
    refute Shortcuts.go_up_pressed?(%{"key" => "0", "code" => "Digit0", "shift" => true})
    refute Shortcuts.go_up_pressed?(%{"key" => "§", "code" => "Digit3", "shift" => false})
  end
end
