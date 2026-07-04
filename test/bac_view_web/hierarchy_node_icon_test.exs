defmodule BacViewWeb.HierarchyNodeIconTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.HierarchyNodeIcon

  test "maps known structured view node types to icons" do
    assert HierarchyNodeIcon.name(:building) == "hero-building-office-2"
    assert HierarchyNodeIcon.name(:floor) == "hero-bars-3-bottom-left"
    assert HierarchyNodeIcon.name(:room) == "hero-home-modern"
    assert HierarchyNodeIcon.name(:equipment) == "hero-wrench-screwdriver"
    assert HierarchyNodeIcon.name(:zone) == "hero-view-columns"
    assert HierarchyNodeIcon.name(:collection) == "hero-folder-open"
  end

  test "falls back for unknown or missing node types" do
    assert HierarchyNodeIcon.name(nil) == "hero-folder"
    assert HierarchyNodeIcon.name(:unknown) == "hero-folder"
    assert HierarchyNodeIcon.name(:not_a_real_type) == "hero-folder"
  end

  test "assigns color classes by node category" do
    assert HierarchyNodeIcon.color_class(:building) == "text-[var(--bac-amber)]"
    assert HierarchyNodeIcon.color_class(:equipment) == "text-[var(--bac-accent)]"
    assert HierarchyNodeIcon.color_class(:organizational) == "text-[var(--bac-text-muted)]"
    assert HierarchyNodeIcon.color_class(nil) == "text-[var(--bac-amber)]"
  end

  test "builds combined icon classes" do
    assert HierarchyNodeIcon.icon_class(:floor, "size-5") ==
             "size-5 shrink-0 text-[var(--bac-amber)]"
  end

  test "tooltip returns trimmed node subtype or nil" do
    assert HierarchyNodeIcon.tooltip("AHU Supply") == "AHU Supply"
    assert HierarchyNodeIcon.tooltip("  ") == nil
    assert HierarchyNodeIcon.tooltip(nil) == nil
  end
end
