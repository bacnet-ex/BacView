defmodule BacView.BACnet.NameHierarchyBuilder do
  @moduledoc """
  Builds a hierarchy tree from BACnet object names using delimiter or position splits.
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.HierarchyNode
  alias BacView.BACnet.HierarchySplit
  alias BacView.NaturalSort

  @folder_type HierarchyNode.folder_type()

  @type result :: %{
          roots: [HierarchyNode.t()],
          all_nodes: %{String.t() => HierarchyNode.t()},
          structured_view_count: non_neg_integer(),
          cycles: [String.t()],
          empty?: boolean(),
          source: :name,
          split: HierarchySplit.t()
        }

  @spec build([map()], HierarchySplit.t()) :: result
  def build(objects, split) when is_list(objects) do
    split_fn =
      case split do
        {:delimiter, delim} -> &split_by_delimiter(&1, delim)
        {:positions, positions} -> &split_by_positions(&1, positions)
      end

    roots =
      objects
      |> Enum.reject(&(&1.type == :structured_view))
      |> Enum.reduce(empty_tree(), fn obj, tree ->
        name = object_name(obj)
        segments = split_fn.(name)
        insert_object(tree, segments, obj)
      end)
      |> tree_to_nodes([])
      |> sort_nodes()

    all_nodes = index_nodes(roots)

    %{
      roots: roots,
      all_nodes: all_nodes,
      structured_view_count: 0,
      cycles: [],
      empty?: roots == [],
      source: :name,
      split: split
    }
  end

  defp empty_tree(), do: %{leaves: [], folders: %{}}

  defp object_name(%{name: name}) when is_binary(name) and name != "", do: name

  defp object_name(%{type: type, instance: instance}),
    do: "#{type}:#{instance}"

  defp object_name(_obj), do: ""

  defp split_by_delimiter(name, :all_special) when is_binary(name) and name != "" do
    String.split(name, ~r/[^A-Za-z0-9]+/, trim: true)
  end

  defp split_by_delimiter(name, delimiter) when is_binary(name) and name != "" do
    name
    |> String.split(delimiter, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_by_delimiter(_name, _delimiter), do: []

  defp split_by_positions(name, positions)
       when is_binary(name) and name != "" and is_list(positions) do
    {segments, rest} =
      Enum.reduce(positions, {[], name}, fn pos, {acc, remaining} ->
        if remaining == "" or pos <= 0 do
          {acc, remaining}
        else
          take = min(pos, byte_size(remaining))
          segment = binary_part(remaining, 0, take)
          leftover = binary_part(remaining, take, byte_size(remaining) - take)
          {[segment | acc], leftover}
        end
      end)

    segments =
      if rest == "" do
        segments
      else
        [rest | segments]
      end

    segments
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end

  defp split_by_positions(_name, _positions), do: []

  defp insert_object(tree, [], _obj), do: tree

  defp insert_object(tree, [_last_segment], obj) do
    %{tree | leaves: [obj | tree.leaves]}
  end

  defp insert_object(tree, [segment | rest], obj) do
    folder = Map.get(tree.folders, segment, empty_tree())
    updated = insert_object(folder, rest, obj)

    %{tree | folders: Map.put(tree.folders, segment, updated)}
  end

  defp tree_to_nodes(%{leaves: leaves, folders: folders}, path_segments) do
    folder_nodes =
      Enum.map(folders, fn {segment, subtree} ->
        next_path = Enum.reverse([segment | Enum.reverse(path_segments)])
        children = tree_to_nodes(subtree, next_path)
        folder_node(next_path, segment, children)
      end)

    leaf_nodes = Enum.map(leaves, &object_leaf_node/1)
    Enum.reverse(folder_nodes, leaf_nodes)
  end

  defp folder_node(path_segments, name, children) do
    instance = folder_instance(path_segments)
    oid = %ObjectIdentifier{type: @folder_type, instance: instance}

    %HierarchyNode{
      object_id: oid,
      type: @folder_type,
      instance: instance,
      name: name,
      type_label: "Ordner",
      node_type: :collection,
      children: children,
      child_count: length(children)
    }
  end

  defp object_leaf_node(obj) do
    oid = %ObjectIdentifier{type: obj.type, instance: obj.instance}

    %HierarchyNode{
      object_id: oid,
      type: obj.type,
      instance: obj.instance,
      name: object_name(obj),
      type_label: Map.get(obj, :type_label),
      children: [],
      child_count: 0
    }
  end

  defp folder_instance(path_segments) do
    rem(:erlang.phash2({@folder_type, path_segments}), 2_147_483_647)
  end

  defp sort_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.sort_by(&node_sort_key/1)
    |> Enum.map(fn %HierarchyNode{} = node ->
      %HierarchyNode{node | children: sort_nodes(node.children)}
    end)
  end

  defp node_sort_key(%HierarchyNode{} = node) do
    if HierarchyNode.folder?(node) do
      {0, NaturalSort.key(node.name)}
    else
      {1, NaturalSort.key(node.name)}
    end
  end

  defp index_nodes(nodes, acc \\ %{}) do
    Enum.reduce(nodes, acc, fn node, acc ->
      acc
      |> Map.put(HierarchyNode.id(node), node)
      |> then(&index_nodes(node.children, &1))
    end)
  end
end
