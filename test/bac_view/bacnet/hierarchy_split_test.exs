defmodule BacView.BACnet.HierarchySplitTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.HierarchySplit

  test "normalizes delimiter split" do
    assert HierarchySplit.normalize("delimiter,_") == {:delimiter, "_"}
    assert HierarchySplit.normalize("delimiter,.") == {:delimiter, "."}
    assert HierarchySplit.normalize("delimiter,:") == {:delimiter, ":"}
    assert HierarchySplit.normalize("delimiter,#") == {:delimiter, "#"}
    assert HierarchySplit.normalize("delimiter,space") == {:delimiter, " "}
    assert HierarchySplit.normalize("delimiter,all") == {:delimiter, :all_special}
    assert HierarchySplit.normalize("delimiter,|") == {:delimiter, "|"}
    assert HierarchySplit.normalize("delimiter,invalid") == nil
  end

  test "lists printable special delimiter options plus all-special mode" do
    ids = Enum.map(HierarchySplit.delimiter_options(), & &1.id)

    assert "all" in ids
    assert "_" in ids
    assert "#" in ids
    assert "space" in ids
    assert "|" in ids
    assert length(ids) == 34
  end

  test "normalizes position split" do
    assert HierarchySplit.normalize("positions,10,5,8") == {:positions, [10, 5, 8]}
    assert HierarchySplit.normalize("positions,0,5") == nil
    assert HierarchySplit.normalize("positions,abc") == nil
  end

  test "encodes split config" do
    assert HierarchySplit.encode({:delimiter, "_"}) == "delimiter,_"
    assert HierarchySplit.encode({:delimiter, :all_special}) == "delimiter,all"
    assert HierarchySplit.encode({:delimiter, " "}) == "delimiter,space"
    assert HierarchySplit.encode({:positions, [10, 5, 8]}) == "positions,10,5,8"
  end

  test "parse_form respects selected mode" do
    assert HierarchySplit.parse_form(%{"mode" => "delimiter", "delimiter" => "_"}) ==
             {:delimiter, "_"}

    assert HierarchySplit.parse_form(%{"mode" => "delimiter", "delimiter" => "all"}) ==
             {:delimiter, :all_special}

    assert HierarchySplit.parse_form(%{"mode" => "positions", "positions" => "10, 5, 8"}) ==
             {:positions, [10, 5, 8]}
  end
end
