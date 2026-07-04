defmodule BacView.MapHelpersTest do
  use ExUnit.Case, async: true

  alias BacView.MapHelpers

  test "update/2 adds keys that are missing from the map" do
    assert MapHelpers.update(%{a: 1}, %{b: 2}) == %{a: 1, b: 2}
  end

  test "update/2 overwrites existing keys" do
    assert MapHelpers.update(%{a: 1}, %{a: 2}) == %{a: 2}
  end

  test "plain map update syntax raises for new keys on OTP 27+" do
    assert_raise KeyError, fn ->
      Code.eval_string("%{%{} | new_key: 1}")
    end
  end
end
