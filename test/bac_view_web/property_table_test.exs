defmodule BacViewWeb.PropertyTableTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.PropertyTable

  test "sorted_properties sorts by name and toggles direction" do
    properties = [
      %{property: :b, property_name: "beta", type: "REAL", value_formatted: "2", writable: false},
      %{
        property: :a,
        property_name: "alpha",
        type: "BOOLEAN",
        value_formatted: "1",
        writable: true
      }
    ]

    assert [%{property_name: "alpha"}, %{property_name: "beta"}] =
             PropertyTable.sorted_properties(properties, "name", :asc)

    assert [%{property_name: "beta"}, %{property_name: "alpha"}] =
             PropertyTable.sorted_properties(properties, "name", :desc)
  end

  test "toggle_sort cycles asc and desc" do
    assert PropertyTable.toggle_sort(nil, :asc, "value") == {"value", :asc}
    assert PropertyTable.toggle_sort("value", :asc, "value") == {"value", :desc}
    assert PropertyTable.toggle_sort("value", :desc, "value") == {"value", :asc}
    assert PropertyTable.toggle_sort("name", :asc, "value") == {"value", :asc}
  end
end
