defmodule BacView.BACnet.NameHierarchyBuilderTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.HierarchyNode
  alias BacView.BACnet.NameHierarchyBuilder

  test "builds hierarchy from delimiter split" do
    objects = [
      %{type: :analog_input, instance: 1, name: "Building.Floor1.Room Temp", type_label: "AI"},
      %{type: :analog_input, instance: 2, name: "Building.Floor2.Room Temp", type_label: "AI"},
      %{type: :binary_input, instance: 3, name: "Door", type_label: "BI"}
    ]

    result = NameHierarchyBuilder.build(objects, {:delimiter, "."})

    refute result.empty?
    assert result.source == :name

    building = Enum.find(result.roots, &(&1.name == "Building"))
    assert building.type == HierarchyNode.folder_type()
    assert length(building.children) == 2

    floor1 = Enum.find(building.children, &(&1.name == "Floor1"))
    assert floor1.type == HierarchyNode.folder_type()
    refute Enum.any?(floor1.children, &(&1.name == "Room Temp"))

    [room_temp] = floor1.children
    assert room_temp.type == :analog_input
    assert room_temp.instance == 1
    assert room_temp.name == "Building.Floor1.Room Temp"

    assert Enum.any?(result.roots, &(&1.type == :binary_input and &1.instance == 3))
  end

  test "builds hierarchy from position split" do
    objects = [
      %{type: :analog_input, instance: 1, name: "ABCDEFGHIJKLMNOP", type_label: "AI"}
    ]

    result = NameHierarchyBuilder.build(objects, {:positions, [4, 3]})

    [root] = result.roots
    assert root.name == "ABCD"
    [child] = root.children
    assert child.name == "EFG"
    refute Enum.any?(child.children, &(&1.name == "HIJKLMNOP"))

    [leaf] = child.children
    assert leaf.type == :analog_input
    assert leaf.instance == 1
  end

  test "places single-segment names at the root" do
    objects = [
      %{type: :analog_input, instance: 1, name: "Room Temp", type_label: "AI"}
    ]

    [leaf] = NameHierarchyBuilder.build(objects, {:delimiter, "."}).roots
    assert leaf.type == :analog_input
    assert leaf.name == "Room Temp"
  end

  test "builds hierarchy from all-special delimiter split without a folder for the last segment" do
    objects = [
      %{type: :analog_input, instance: 1, name: "Building_Floor-1.Room:Temp", type_label: "AI"}
    ]

    result = NameHierarchyBuilder.build(objects, {:delimiter, :all_special})
    refute result.empty?

    [building] = result.roots
    assert building.name == "Building"

    [floor] = building.children
    assert floor.name == "Floor"

    [one] = floor.children
    assert one.name == "1"

    [room] = one.children
    assert room.name == "Room"
    refute Enum.any?(room.children, &(&1.name == "Temp"))

    [leaf] = room.children
    assert leaf.type == :analog_input
    assert leaf.instance == 1
    assert leaf.name == "Building_Floor-1.Room:Temp"
  end

  test "ignores structured view objects" do
    objects = [
      %{type: :structured_view, instance: 1, name: "SV", type_label: "SV"},
      %{type: :analog_input, instance: 2, name: "A.B", type_label: "AI"}
    ]

    result = NameHierarchyBuilder.build(objects, {:delimiter, "."})
    refute Enum.any?(result.roots, &(&1.type == :structured_view))
  end
end
