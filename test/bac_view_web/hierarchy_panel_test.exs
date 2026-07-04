defmodule BacViewWeb.HierarchyPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.HierarchyPanel

  defp base_assigns(entries) do
    %{
      hierarchy_view: "explorer",
      hierarchy_view_paths: %{
        "explorer" => "/devices/1?tab=hierarchy&hierarchy_view=explorer",
        "tree" => "/devices/1?tab=hierarchy&hierarchy_view=tree",
        "objects_fallback" => "/devices/1?tab=objects"
      },
      hierarchy_root_path: "/devices/1?tab=hierarchy&hierarchy_view=explorer",
      hierarchy_path_links: [],
      device_id: 1,
      roots: [],
      entries: entries,
      empty_hierarchy?: false,
      locale: "de",
      locale_version: 0
    }
  end

  defp object_entry(overrides) do
    Map.merge(
      %{
        kind: :object,
        type: :analog_input,
        instance: 1,
        name: "Room Temp",
        description: "Supply",
        annotation: nil,
        writable: false,
        commandable: false,
        present_value_formatted: "21.5 °C",
        active_priority: nil,
        status_flags: nil
      },
      overrides
    )
  end

  test "live badge appears next to the object name" do
    subscribed_keys = MapSet.new([{:analog_input, 1, :present_value}])

    entries = [
      object_entry(%{instance: 1, name: "Room Temp"}),
      object_entry(%{instance: 2, name: "Supply Air"})
    ]

    html =
      render_component(
        &HierarchyPanel.hierarchy_panel/1,
        base_assigns(entries) |> Map.put(:subscribed_keys, subscribed_keys)
      )

    document = LazyHTML.from_fragment(html)
    row = LazyHTML.query_by_id(document, "hierarchy-entry-analog_input-1")
    cells = Enum.to_list(LazyHTML.query(row, "td"))
    name_cell = Enum.at(cells, 1)
    pv_cell = Enum.at(cells, 3)

    assert Enum.count(LazyHTML.query(name_cell, ".bac-badge-success")) == 1
    assert Enum.count(LazyHTML.query(pv_cell, ".bac-badge-success")) == 0
    assert LazyHTML.text(pv_cell) =~ "21.5 °C"
  end

  test "writable present values use bac-cell-writable on the value text" do
    entries = [
      object_entry(%{instance: 1, writable: false, present_value_formatted: "active"}),
      object_entry(%{instance: 2, writable: true, present_value_formatted: "22.0 °C"})
    ]

    html =
      render_component(&HierarchyPanel.hierarchy_panel/1, base_assigns(entries))

    assert html |> String.split("bac-cell-writable") |> length() == 2
    assert html =~ "22.0 °C"
    assert html =~ ~s(id="hierarchy-entry-analog_input-2")
    refute html =~ "whitespace-nowrap bac-cell-writable"
    refute html =~ ~r/bac-cell-writable[^<]*active/s
  end
end
