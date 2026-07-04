defmodule BacView.BACnet.HierarchyBuilderTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.DeviceObjectRef
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.HierarchyBuilder

  test "builds nested structured view hierarchy" do
    root_oid = %ObjectIdentifier{type: :structured_view, instance: 1}
    child_sv_oid = %ObjectIdentifier{type: :structured_view, instance: 2}
    ai_oid = %ObjectIdentifier{type: :analog_input, instance: 10}

    root_sv = %{
      object_name: "Building",
      node_type: :device,
      node_subtype: "Site Root",
      subordinate_list: [
        %DeviceObjectRef{device_identifier: nil, object_identifier: child_sv_oid},
        %DeviceObjectRef{device_identifier: nil, object_identifier: ai_oid}
      ],
      subordinate_annotations: ["Floor", "Temp"]
    }

    child_sv = %{
      object_name: "Floor 1",
      node_type: :device,
      node_subtype: "Ground Floor",
      subordinate_list: [],
      subordinate_annotations: []
    }

    ai_obj = %{object_name: "Room Temp"}

    scanned = [
      {root_oid, root_sv},
      {child_sv_oid, child_sv},
      {ai_oid, ai_obj}
    ]

    objects = [
      %{type: :structured_view, instance: 1, name: "Building", type_label: "SV"},
      %{type: :structured_view, instance: 2, name: "Floor 1", type_label: "SV"},
      %{type: :analog_input, instance: 10, name: "Room Temp", type_label: "AI"}
    ]

    result = HierarchyBuilder.build(scanned, objects)

    assert result.structured_view_count == 2
    assert length(result.roots) == 1
    [root] = result.roots
    assert root.name == "Building"
    assert root.node_subtype == "Site Root"
    assert length(root.children) == 2

    floor_sv = Enum.find(root.children, &(&1.type == :structured_view))
    assert floor_sv.node_subtype == "Ground Floor"
    assert Enum.any?(root.children, &(&1.type == :structured_view and &1.instance == 2))
    assert Enum.any?(root.children, &(&1.type == :analog_input and &1.annotation == "Temp"))
  end

  test "sorts structured views before other objects alphanumerically at each level" do
    root_oid = %ObjectIdentifier{type: :structured_view, instance: 1}

    sv_z_oid = %ObjectIdentifier{type: :structured_view, instance: 3}
    sv_a_oid = %ObjectIdentifier{type: :structured_view, instance: 4}
    ai_oid = %ObjectIdentifier{type: :analog_input, instance: 2}
    bi_oid = %ObjectIdentifier{type: :binary_input, instance: 1}

    root_sv = %{
      object_name: "Building",
      node_type: :device,
      subordinate_list: [
        %DeviceObjectRef{device_identifier: nil, object_identifier: bi_oid},
        %DeviceObjectRef{device_identifier: nil, object_identifier: sv_z_oid},
        %DeviceObjectRef{device_identifier: nil, object_identifier: ai_oid},
        %DeviceObjectRef{device_identifier: nil, object_identifier: sv_a_oid}
      ],
      subordinate_annotations: []
    }

    scanned = [
      {root_oid, root_sv},
      {sv_z_oid, %{object_name: "Zebra", subordinate_list: [], subordinate_annotations: []}},
      {sv_a_oid,
       %{object_name: "Alpha Floor", subordinate_list: [], subordinate_annotations: []}},
      {ai_oid, %{object_name: "Alpha"}},
      {bi_oid, %{object_name: "Beta"}}
    ]

    objects = [
      %{type: :structured_view, instance: 1, name: "Building", type_label: "SV"},
      %{type: :structured_view, instance: 3, name: "Zebra", type_label: "SV"},
      %{type: :structured_view, instance: 4, name: "Alpha Floor", type_label: "SV"},
      %{type: :analog_input, instance: 2, name: "Alpha", type_label: "AI"},
      %{type: :binary_input, instance: 1, name: "Beta", type_label: "BI"}
    ]

    [root] = HierarchyBuilder.build(scanned, objects).roots

    assert Enum.map(root.children, & &1.name) == [
             "Alpha Floor",
             "Zebra",
             "Alpha",
             "Beta"
           ]
  end

  test "sorts object names with natural numeric order" do
    root_oid = %ObjectIdentifier{type: :structured_view, instance: 1}
    room_10_oid = %ObjectIdentifier{type: :analog_input, instance: 10}
    room_2_oid = %ObjectIdentifier{type: :analog_input, instance: 2}
    room_1_oid = %ObjectIdentifier{type: :analog_input, instance: 1}

    root_sv = %{
      object_name: "Building",
      node_type: :device,
      subordinate_list: [
        %DeviceObjectRef{device_identifier: nil, object_identifier: room_10_oid},
        %DeviceObjectRef{device_identifier: nil, object_identifier: room_2_oid},
        %DeviceObjectRef{device_identifier: nil, object_identifier: room_1_oid}
      ],
      subordinate_annotations: []
    }

    scanned = [
      {root_oid, root_sv},
      {room_10_oid, %{object_name: "Room 10"}},
      {room_2_oid, %{object_name: "Room 2"}},
      {room_1_oid, %{object_name: "Room 1"}}
    ]

    objects = [
      %{type: :structured_view, instance: 1, name: "Building", type_label: "SV"},
      %{type: :analog_input, instance: 10, name: "Room 10", type_label: "AI"},
      %{type: :analog_input, instance: 2, name: "Room 2", type_label: "AI"},
      %{type: :analog_input, instance: 1, name: "Room 1", type_label: "AI"}
    ]

    [root] = HierarchyBuilder.build(scanned, objects).roots

    assert Enum.map(root.children, & &1.name) == ["Room 1", "Room 2", "Room 10"]
  end

  test "filter_tree matches by name" do
    node = %BacView.BACnet.HierarchyNode{
      type: :analog_input,
      instance: 1,
      name: "Supply Air",
      children: []
    }

    {filtered, count} = HierarchyBuilder.filter_tree([node], "supply")
    assert count == 1
    assert hd(filtered).name == "Supply Air"
  end

  test "filter_tree supports exclusion tokens" do
    nodes = [
      %BacView.BACnet.HierarchyNode{
        type: :analog_input,
        instance: 1,
        name: "Supply Air",
        children: []
      },
      %BacView.BACnet.HierarchyNode{
        type: :analog_input,
        instance: 2,
        name: "Return Air",
        children: []
      }
    ]

    {filtered, count} = HierarchyBuilder.filter_tree(nodes, "-supply")
    assert count == 1
    assert hd(filtered).name == "Return Air"
  end
end
