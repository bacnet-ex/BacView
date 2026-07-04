defmodule BacViewWeb.ObjectTypeIconTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.{Heroicons, ObjectTypeIcon}

  test "all object type icons exist in heroicons bundle" do
    for icon <- ObjectTypeIcon.names() do
      assert Heroicons.svg(icon) =~ "<svg", "missing icon #{icon}"
    end
  end

  test "binary_value uses a valid icon" do
    assert ObjectTypeIcon.name(:binary_value) == "hero-arrows-right-left"
    assert Heroicons.svg(ObjectTypeIcon.name(:binary_value)) =~ "<path"
  end
end
