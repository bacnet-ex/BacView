defmodule BacViewWeb.HierarchyExplorerTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.HierarchyNode
  alias BacViewWeb.HierarchyExplorer

  test "folder_entries lists folders before objects with natural name order" do
    roots = [
      %HierarchyNode{
        type: :structured_view,
        instance: 1,
        name: "Building",
        node_type: :building,
        node_subtype: "Main Campus",
        children: [
          %HierarchyNode{
            type: :structured_view,
            instance: 2,
            name: "Floor 2",
            node_type: :floor,
            node_subtype: "Level 2",
            child_count: 1
          },
          %HierarchyNode{type: :analog_input, instance: 2, name: "Room 2", annotation: "Temp"},
          %HierarchyNode{type: :analog_input, instance: 10, name: "Room 10", annotation: "Sensor"}
        ],
        child_count: 3
      }
    ]

    objects = [
      %{type: :analog_input, instance: 10, name: "Room 10", description: "Ten", writable: false},
      %{type: :analog_input, instance: 2, name: "Room 2", description: "Two", writable: true},
      %{type: :structured_view, instance: 1, name: "Building", description: "Main site"},
      %{type: :structured_view, instance: 2, name: "Floor 2", description: "Second floor"}
    ]

    [root_entry] = HierarchyExplorer.folder_entries(roots, [], objects)
    assert root_entry.kind == :folder
    assert root_entry.name == "Building"
    assert root_entry.description == "Main site"
    assert Map.has_key?(root_entry, :node_type)

    entries = HierarchyExplorer.folder_entries(roots, [{:structured_view, 1}], objects)

    assert Enum.map(entries, & &1.kind) == [:folder, :object, :object]
    assert hd(entries).name == "Floor 2"
    assert hd(entries).description == "Second floor"
    assert hd(entries).node_type == :floor
    assert hd(entries).node_subtype == "Level 2"
    [_, room2, room10] = entries
    assert room2.name == "Room 2"
    assert room2.annotation == "Temp"
    assert room2.description == "Two"
    assert room2.writable
    assert room10.name == "Room 10"
    refute room10.writable
  end

  test "status_flag_counts aggregates active flags from all subordinate objects" do
    building = %HierarchyNode{
      type: :structured_view,
      instance: 1,
      name: "Building",
      children: [
        %HierarchyNode{
          type: :structured_view,
          instance: 2,
          name: "Floor 2",
          children: [
            %HierarchyNode{type: :binary_input, instance: 1, name: "Door"}
          ],
          child_count: 1
        },
        %HierarchyNode{type: :analog_input, instance: 2, name: "Room Temp"}
      ],
      child_count: 2
    }

    flags = fn overrides ->
      struct(
        StatusFlags,
        Map.merge(
          %{in_alarm: false, fault: false, overridden: false, out_of_service: false},
          Map.new(overrides)
        )
      )
    end

    objects_index = %{
      {:binary_input, 1} => %{status_flags: flags.(fault: true)},
      {:analog_input, 2} => %{status_flags: flags.(in_alarm: true, overridden: true)}
    }

    assert HierarchyExplorer.status_flag_counts(building, objects_index) == %{
             in_alarm: 1,
             fault: 1,
             overridden: 1,
             out_of_service: 0
           }

    floor = Enum.at(building.children, 0)

    assert HierarchyExplorer.status_flag_counts(floor, objects_index) == %{
             in_alarm: 0,
             fault: 1,
             overridden: 0,
             out_of_service: 0
           }
  end

  test "folder entries include aggregated status flag counts" do
    roots = [
      %HierarchyNode{
        type: :structured_view,
        instance: 1,
        name: "Building",
        children: [
          %HierarchyNode{type: :analog_input, instance: 2, name: "Room Temp"}
        ],
        child_count: 1
      }
    ]

    objects = [
      %{
        type: :structured_view,
        instance: 1,
        name: "Building",
        description: "Main site"
      },
      %{
        type: :analog_input,
        instance: 2,
        name: "Room Temp",
        status_flags: %StatusFlags{
          in_alarm: true,
          fault: false,
          overridden: false,
          out_of_service: false
        }
      }
    ]

    [folder] = HierarchyExplorer.folder_entries(roots, [], objects)
    assert folder.status_flag_counts == %{in_alarm: 1, fault: 0, overridden: 0, out_of_service: 0}
  end

  test "selection expands structured views to descendant object keys" do
    building = %HierarchyNode{
      type: :structured_view,
      instance: 1,
      name: "Building",
      children: [
        %HierarchyNode{type: :analog_input, instance: 2, name: "Temp"},
        %HierarchyNode{
          type: :structured_view,
          instance: 3,
          name: "Floor",
          children: [%HierarchyNode{type: :binary_input, instance: 4, name: "Door"}],
          child_count: 1
        }
      ],
      child_count: 2
    }

    selectable = MapSet.new([{:analog_input, 2}, {:binary_input, 4}])

    assert HierarchyExplorer.selection_keys_for_node(building, selectable) ==
             selectable

    floor = Enum.at(building.children, 1)

    assert HierarchyExplorer.selection_keys_for_node(floor, selectable) ==
             MapSet.new([{:binary_input, 4}])
  end

  test "visible_selection_keys includes folder descendants and visible objects" do
    entries = [
      %{
        kind: :folder,
        type: :structured_view,
        instance: 1,
        selectable_descendant_keys: MapSet.new([{:analog_input, 2}])
      },
      %{kind: :object, type: :binary_input, instance: 4}
    ]

    selectable = MapSet.new([{:analog_input, 2}, {:binary_input, 4}])

    assert HierarchyExplorer.visible_selection_keys(entries, selectable) ==
             selectable
  end

  test "filter_entries matches visible folder and object fields in current view" do
    entries = [
      %{
        kind: :folder,
        type: :structured_view,
        instance: 2,
        name: "Floor 2",
        description: "Second floor",
        annotation: nil
      },
      %{
        kind: :object,
        type: :analog_input,
        instance: 2,
        name: "Room Temp",
        description: "Supply air",
        annotation: "AI-2",
        type_label: "Analog Input",
        present_value_formatted: "21.5 °C"
      },
      %{
        kind: :object,
        type: :binary_input,
        instance: 4,
        name: "Door",
        description: "Entrance",
        annotation: nil,
        type_label: "Binary Input",
        present_value_formatted: "active"
      }
    ]

    {filtered, count} = HierarchyExplorer.filter_entries(entries, "supply")
    assert count == 1
    assert [%{name: "Room Temp"}] = filtered

    {filtered, count} = HierarchyExplorer.filter_entries(entries, "floor")
    assert count == 1
    assert [%{kind: :folder, name: "Floor 2"}] = filtered

    {filtered, count} = HierarchyExplorer.filter_entries(entries, "")
    assert count == 3
    assert length(filtered) == 3
  end

  test "filter_entries supports exclusion tokens" do
    entries = [
      %{
        kind: :object,
        type: :analog_input,
        instance: 2,
        name: "Room Temp",
        description: "Supply air",
        annotation: "AI-2",
        type_label: "Analog Input",
        present_value_formatted: "21.5 °C"
      },
      %{
        kind: :object,
        type: :binary_input,
        instance: 4,
        name: "Door",
        description: "Entrance",
        annotation: nil,
        type_label: "Binary Input",
        present_value_formatted: "active"
      }
    ]

    {filtered, count} = HierarchyExplorer.filter_entries(entries, "-supply")
    assert count == 1
    assert [%{name: "Door"}] = filtered
  end

  test "breadcrumbs builds path segments" do
    child = %HierarchyNode{
      type: :structured_view,
      instance: 2,
      name: "Floor",
      children: [],
      child_count: 0
    }

    roots = [
      %HierarchyNode{
        type: :structured_view,
        instance: 1,
        name: "Building",
        children: [child],
        child_count: 1
      }
    ]

    assert HierarchyExplorer.breadcrumbs(roots, [{:structured_view, 1}, {:structured_view, 2}]) ==
             [
               {"Building", [{:structured_view, 1}]},
               {"Floor", [{:structured_view, 1}, {:structured_view, 2}]}
             ]
  end
end
