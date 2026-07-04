defmodule BacViewWeb.HeroiconsTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.Heroicons

  test "loads known outline icons" do
    assert Heroicons.svg("hero-arrow-left") =~ "<svg"
    assert Heroicons.svg("hero-chevron-up") =~ "<path"
    assert Heroicons.svg("hero-funnel") =~ "<path"
  end

  test "loads solid, mini, and micro variants" do
    assert Heroicons.svg("hero-x-mark-solid") =~ "<svg"
    assert Heroicons.svg("hero-computer-desktop-micro") =~ "<svg"
  end

  test "returns nil for unknown icons" do
    assert Heroicons.svg("hero-not-a-real-icon") == nil
    assert Heroicons.svg("invalid") == nil
  end
end
