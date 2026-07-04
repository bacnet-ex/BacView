defmodule BacView.NaturalSortTest do
  use ExUnit.Case, async: true

  alias BacView.NaturalSort

  test "key sorts numeric segments naturally" do
    labels = ["Room 10", "Room 2", "Room 1"]

    assert Enum.sort_by(labels, &NaturalSort.key/1) == [
             "Room 1",
             "Room 2",
             "Room 10"
           ]
  end

  test "key is case-insensitive" do
    assert NaturalSort.key("Alpha") == NaturalSort.key("alpha")
  end

  test "key handles nil as empty" do
    assert NaturalSort.key(nil) == []
  end
end
