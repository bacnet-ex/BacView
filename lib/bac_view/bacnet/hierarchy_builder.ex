defmodule BacView.BACnet.HierarchyBuilder do
  @moduledoc """
  Builds a Structured View hierarchy from scanned BACnet objects.
  """

  alias BACnet.Protocol.DeviceObjectRef
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.HierarchyNode
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.NaturalSort
  alias BacViewWeb.SearchQuery

  @type result :: %{
          roots: [HierarchyNode.t()],
          all_nodes: %{String.t() => HierarchyNode.t()},
          structured_view_count: non_neg_integer(),
          cycles: [String.t()],
          empty?: boolean()
        }

  @doc """
  Builds the SV hierarchy from `scanned` device objects (`{ObjectIdentifier, object}` tuples)
  and summarized `objects` used for display metadata.
  """
  @spec build([{ObjectIdentifier.t(), map()}], [map()]) :: result
  def build(scanned, objects) when is_list(scanned) and is_list(objects) do
    summary_index = Map.new(objects, fn obj -> {{obj.type, obj.instance}, obj} end)

    sv_map =
      scanned
      |> Enum.filter(fn {%{type: type}, _scanned} -> type == :structured_view end)
      |> Map.new(fn {oid, sv} -> {{oid.type, oid.instance}, {oid, sv}} end)

    referenced_keys =
      sv_map
      |> Enum.flat_map(fn {_key, {_oid, sv}} ->
        sv
        |> extract_subordinates()
        |> Enum.map(&ref_key/1)
        |> Enum.reject(&is_nil/1)
      end)
      |> MapSet.new()

    {roots, cycles} =
      sv_map
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(referenced_keys, &1))
      |> Enum.sort()
      |> Enum.map_reduce([], fn key, cycles_acc ->
        {oid, sv} = Map.fetch!(sv_map, key)

        {node, cycles_acc} =
          build_node(key, oid, sv, sv_map, summary_index, MapSet.new(), cycles_acc)

        {node, cycles_acc}
      end)

    roots = sort_nodes(roots)
    all_nodes = index_nodes(roots)

    structured_view_count = map_size(sv_map)

    %{
      roots: roots,
      all_nodes: all_nodes,
      structured_view_count: structured_view_count,
      cycles: Enum.uniq(cycles),
      empty?: structured_view_count == 0 or roots == []
    }
  end

  defp build_node(key, oid, sv, sv_map, summary_index, visited, cycles_acc) do
    if MapSet.member?(visited, key) do
      summary = Map.get(summary_index, key, %{})
      node = cycle_node(oid, summary)
      {node, [HierarchyNode.id(node) | cycles_acc]}
    else
      visited = MapSet.put(visited, key)
      summary = Map.get(summary_index, key, %{})
      subordinates = extract_subordinates(sv)
      annotations = extract_annotations(sv)

      {children, cycles_acc} =
        Enum.map_reduce(Enum.with_index(subordinates), cycles_acc, fn {ref, idx}, acc ->
          case ref_key(ref) do
            nil ->
              {nil, acc}

            child_key ->
              annotation = Enum.at(annotations, idx)
              child_summary = Map.get(summary_index, child_key, %{})

              if Map.has_key?(sv_map, child_key) do
                {child_oid, child_sv} = Map.fetch!(sv_map, child_key)

                {%HierarchyNode{} = child_node, acc} =
                  build_node(child_key, child_oid, child_sv, sv_map, summary_index, visited, acc)

                child_node = %HierarchyNode{
                  child_node
                  | annotation: annotation || child_node.annotation
                }

                {child_node, acc}
              else
                child_oid = ref.object_identifier

                {leaf_node(child_oid, child_summary, annotation), acc}
              end
          end
        end)

      children = Enum.reject(children, &is_nil/1)

      node = %HierarchyNode{
        object_id: oid,
        type: oid.type,
        instance: oid.instance,
        name: summary[:name] || Map.get(sv, :object_name),
        type_label: ObjectTypes.label(:structured_view),
        node_type: Map.get(sv, :node_type),
        node_subtype: Map.get(sv, :node_subtype),
        children: children,
        child_count: length(children)
      }

      {node, cycles_acc}
    end
  end

  defp leaf_node(%ObjectIdentifier{} = oid, summary, annotation) do
    %HierarchyNode{
      object_id: oid,
      type: oid.type,
      instance: oid.instance,
      name: summary[:name],
      annotation: annotation,
      type_label: summary[:type_label] || ObjectTypes.label(oid.type),
      children: [],
      child_count: 0
    }
  end

  defp cycle_node(%ObjectIdentifier{} = oid, summary) do
    %HierarchyNode{
      object_id: oid,
      type: oid.type,
      instance: oid.instance,
      name: summary[:name],
      type_label: ObjectTypes.label(:structured_view),
      children: [],
      child_count: 0,
      cycle: true
    }
  end

  defp extract_subordinates(sv) do
    case Map.get(sv, :subordinate_list) do
      list when is_list(list) -> normalize_refs(list)
      _sv -> []
    end
  end

  defp extract_annotations(sv) do
    case Map.get(sv, :subordinate_annotations) do
      list when is_list(list) -> normalize_strings(list)
      _sv -> []
    end
  end

  defp normalize_refs(list) do
    list
    |> Enum.map(fn
      %DeviceObjectRef{} = ref ->
        ref

      %{value: %DeviceObjectRef{} = ref} ->
        ref

      %{object_identifier: _list} = ref ->
        struct(DeviceObjectRef, Map.take(ref, [:device_identifier, :object_identifier]))

      _list ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_strings(list) do
    Enum.map(list, fn
      s when is_binary(s) -> s
      %{value: v} -> to_string(v)
      v -> to_string(v)
    end)
  end

  defp ref_key(%DeviceObjectRef{
         object_identifier: %ObjectIdentifier{type: type, instance: instance}
       }),
       do: {type, instance}

  defp ref_key(_ref_key), do: nil

  @doc """
  Filters a hierarchy tree by search query (case-insensitive).
  Returns `{filtered_roots, visible_node_count}`.
  """
  @spec filter_tree([HierarchyNode.t()], String.t()) :: {[HierarchyNode.t()], non_neg_integer()}
  def filter_tree(roots, ""), do: {roots, count_nodes(roots)}

  def filter_tree(roots, query) do
    parsed = SearchQuery.parse(query)

    filtered =
      Enum.flat_map(roots, fn root ->
        case filter_node(root, parsed) do
          nil -> []
          node -> [node]
        end
      end)

    {filtered, count_nodes(filtered)}
  end

  defp filter_node(%HierarchyNode{} = node, query) do
    self_match? = SearchQuery.matches?(query, node_search_haystack(node))

    filtered_children =
      node.children
      |> Enum.map(&filter_node(&1, query))
      |> Enum.reject(&is_nil/1)

    cond do
      self_match? ->
        %HierarchyNode{node | children: filtered_children, child_count: length(filtered_children)}

      filtered_children != [] ->
        %HierarchyNode{node | children: filtered_children, child_count: length(filtered_children)}

      true ->
        nil
    end
  end

  defp node_search_haystack(%HierarchyNode{} = node) do
    [node.name, node.annotation, "#{node.type}:#{node.instance}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp count_nodes(nodes) do
    Enum.reduce(nodes, 0, fn node, acc -> acc + 1 + count_nodes(node.children) end)
  end

  defp index_nodes(nodes, acc \\ %{}) do
    Enum.reduce(nodes, acc, fn node, acc ->
      acc =
        acc
        |> Map.put(HierarchyNode.id(node), node)
        |> then(&index_nodes(node.children, &1))

      acc
    end)
  end

  defp sort_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.sort_by(&node_sort_key/1)
    |> Enum.map(fn %HierarchyNode{} = node ->
      %HierarchyNode{node | children: sort_nodes(node.children)}
    end)
  end

  defp node_sort_key(%HierarchyNode{type: :structured_view} = node),
    do: {0, NaturalSort.key(node_label(node))}

  defp node_sort_key(node), do: {1, NaturalSort.key(node_label(node))}

  defp node_label(%HierarchyNode{name: name, type: type, instance: instance}) do
    label_or_fallback(name, type, instance)
  end

  defp label_or_fallback(name, _type, _instance) when is_binary(name) and name != "", do: name

  defp label_or_fallback(_name, type, instance), do: "#{type}:#{instance}"
end
