defmodule BacViewWeb.HierarchyExplorer do
  @moduledoc false

  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.HierarchyNode
  alias BacViewWeb.SearchQuery

  @type segment :: {atom(), non_neg_integer()}
  @status_flag_fields [:in_alarm, :fault, :overridden, :out_of_service]
  @empty_status_flag_counts Map.new(@status_flag_fields, &{&1, 0})

  @spec filter_entries([map()], String.t()) :: {[map()], non_neg_integer()}
  def filter_entries(entries, query) when is_list(entries) do
    parsed = SearchQuery.parse(query)

    if parsed.mode == :all do
      {entries, length(entries)}
    else
      filtered =
        Enum.filter(entries, fn entry ->
          SearchQuery.matches?(parsed, entry_search_haystack(entry))
        end)

      {filtered, length(filtered)}
    end
  end

  @spec folder_entries([HierarchyNode.t()], [segment()], [map()], keyword()) :: [map()]
  def folder_entries(roots, path, objects, opts \\ []) when is_list(roots) and is_list(objects) do
    objects_index = Map.new(objects, fn obj -> {{obj.type, obj.instance}, obj} end)
    selectable_keys = Keyword.get(opts, :selectable_keys, MapSet.new())

    case resolve_folder(roots, path) do
      :root ->
        enrich_children(roots, objects_index, selectable_keys)

      {:ok, %HierarchyNode{children: children}} ->
        enrich_children(children, objects_index, selectable_keys)

      :error ->
        []
    end
  end

  @spec descendant_object_keys(HierarchyNode.t()) :: [{atom(), non_neg_integer()}]
  def descendant_object_keys(%HierarchyNode{} = node), do: descendant_object_keys_private(node)

  @spec descendant_selectable_keys(HierarchyNode.t(), MapSet.t()) :: MapSet.t()
  def descendant_selectable_keys(%HierarchyNode{} = node, selectable_keys) do
    node
    |> descendant_object_keys()
    |> Enum.filter(&MapSet.member?(selectable_keys, &1))
    |> MapSet.new()
  end

  @spec find_node([HierarchyNode.t()], {atom(), non_neg_integer()}) :: HierarchyNode.t() | nil
  def find_node(nodes, key) when is_list(nodes) do
    Enum.find_value(nodes, fn node ->
      cond do
        node_key(node) == key -> node
        node.type == :structured_view -> find_node(node.children, key)
        true -> nil
      end
    end)
  end

  @spec visible_selection_keys([map()], MapSet.t()) :: MapSet.t()
  def visible_selection_keys(entries, selectable_keys) when is_list(entries) do
    Enum.reduce(entries, MapSet.new(), fn entry, acc ->
      MapSet.union(acc, entry_selection_keys(entry, selectable_keys))
    end)
  end

  @spec tree_visible_selection_keys([HierarchyNode.t()], MapSet.t()) :: MapSet.t()
  def tree_visible_selection_keys(nodes, selectable_keys) when is_list(nodes) do
    Enum.reduce(nodes, MapSet.new(), fn node, acc ->
      acc
      |> MapSet.union(node_selection_keys(node, selectable_keys))
      |> MapSet.union(tree_visible_selection_keys(node.children, selectable_keys))
    end)
  end

  @spec folder_selected?(MapSet.t(), MapSet.t()) :: boolean()
  def folder_selected?(selected_keys, descendant_keys) do
    descendant_keys != MapSet.new() and MapSet.subset?(descendant_keys, selected_keys)
  end

  @spec selection_keys_for_node(HierarchyNode.t(), MapSet.t()) :: MapSet.t()
  def selection_keys_for_node(%HierarchyNode{type: :structured_view} = node, selectable_keys) do
    descendant_selectable_keys(node, selectable_keys)
  end

  def selection_keys_for_node(%HierarchyNode{} = node, selectable_keys) do
    key = node_key(node)

    if MapSet.member?(selectable_keys, key), do: MapSet.new([key]), else: MapSet.new()
  end

  @spec breadcrumbs([HierarchyNode.t()], [segment()]) :: [{String.t(), [segment()]}]
  def breadcrumbs(roots, path) when is_list(roots) do
    {crumbs_rev, _current_path_rev, _nodes} =
      Enum.reduce(path, {[], [], roots}, fn segment, {crumbs_rev, current_path_rev, nodes} ->
        case find_child(nodes, segment) do
          nil ->
            {crumbs_rev, current_path_rev, []}

          %HierarchyNode{} = node ->
            next_path_rev = [segment | current_path_rev]
            label = node.name || "#{node.type}:#{node.instance}"
            next_path = Enum.reverse(next_path_rev)

            {[{label, next_path} | crumbs_rev], next_path_rev, node.children}
        end
      end)

    Enum.reverse(crumbs_rev)
  end

  @spec append_segment([segment()], segment()) :: [segment()]
  # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
  def append_segment(path, segment) when is_list(path), do: path ++ [segment]

  @spec status_flag_counts(HierarchyNode.t(), map()) :: %{atom() => non_neg_integer()}
  def status_flag_counts(%HierarchyNode{} = node, objects_index) when is_map(objects_index) do
    node
    |> descendant_object_keys()
    |> Enum.reduce(@empty_status_flag_counts, fn key, acc ->
      increment_status_flag_counts(acc, Map.get(objects_index, key, %{}))
    end)
  end

  @spec resolve_folder([HierarchyNode.t()], [segment()]) ::
          :root | {:ok, HierarchyNode.t()} | :error
  def resolve_folder(_roots, []), do: :root

  def resolve_folder(roots, path) when is_list(roots) and is_list(path) do
    case navigate(roots, path) do
      %HierarchyNode{} = node -> {:ok, node}
      nil -> :error
    end
  end

  defp navigate(roots, [segment | rest]) do
    case find_child(roots, segment) do
      nil -> nil
      %HierarchyNode{} = node -> if rest == [], do: node, else: navigate(node.children, rest)
    end
  end

  defp find_child(nodes, {type, instance}) when is_list(nodes) do
    Enum.find(nodes, fn %HierarchyNode{type: node_type, instance: node_instance} ->
      node_type == type and node_instance == instance
    end)
  end

  defp enrich_children(children, objects_index, selectable_keys) when is_list(children) do
    Enum.map(children, &enrich_entry(&1, objects_index, selectable_keys))
  end

  defp enrich_entry(%HierarchyNode{type: :structured_view} = node, objects_index, selectable_keys) do
    object = Map.get(objects_index, {node.type, node.instance}, %{})

    %{
      kind: :folder,
      type: node.type,
      instance: node.instance,
      node_type: node.node_type,
      node_subtype: node.node_subtype,
      name: display_name(node, object),
      annotation: node.annotation,
      description: Map.get(object, :description),
      child_count: node.child_count,
      cycle: node.cycle,
      status_flag_counts: status_flag_counts(node, objects_index),
      selectable_descendant_keys: descendant_selectable_keys(node, selectable_keys)
    }
  end

  defp enrich_entry(%HierarchyNode{} = node, objects_index, _selectable_keys) do
    object = Map.get(objects_index, {node.type, node.instance}, %{})

    %{
      kind: :object,
      type: node.type,
      instance: node.instance,
      annotation: node.annotation,
      name: display_name(node, object),
      description: Map.get(object, :description),
      object: object,
      writable: Map.get(object, :writable, false),
      commandable: Map.get(object, :commandable, false),
      present_value_formatted: Map.get(object, :present_value_formatted, "—"),
      active_priority: Map.get(object, :active_priority),
      status_flags: Map.get(object, :status_flags),
      type_label: Map.get(object, :type_label)
    }
  end

  defp display_name(%HierarchyNode{} = node, object) do
    node.name || Map.get(object, :name) || "#{node.type}:#{node.instance}"
  end

  defp entry_search_haystack(entry) do
    entry
    |> entry_search_fields()
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp entry_search_fields(%{kind: :folder} = entry) do
    [
      entry.name,
      entry.description,
      entry.annotation,
      "#{entry.type}:#{entry.instance}"
    ]
  end

  defp entry_search_fields(%{kind: :object} = entry) do
    [
      entry.name,
      entry.description,
      entry.annotation,
      entry.type_label,
      entry.present_value_formatted,
      "#{entry.type}:#{entry.instance}"
    ]
  end

  defp entry_selection_keys(%{kind: :folder, selectable_descendant_keys: keys}, _selectable_keys),
    do: keys

  defp entry_selection_keys(%{kind: :object, type: type, instance: instance}, selectable_keys) do
    key = {type, instance}
    if MapSet.member?(selectable_keys, key), do: MapSet.new([key]), else: MapSet.new()
  end

  defp node_selection_keys(%HierarchyNode{} = node, selectable_keys) do
    selection_keys_for_node(node, selectable_keys)
  end

  defp node_key(%HierarchyNode{type: type, instance: instance}), do: {type, instance}

  defp descendant_object_keys_private(%HierarchyNode{type: :structured_view, children: children}) do
    Enum.flat_map(children, &descendant_object_keys_private/1)
  end

  defp descendant_object_keys_private(%HierarchyNode{type: type, instance: instance}) do
    [{type, instance}]
  end

  defp increment_status_flag_counts(acc, object) do
    case Map.get(object, :status_flags) do
      %StatusFlags{} = flags ->
        Enum.reduce(@status_flag_fields, acc, fn flag, counts ->
          if Map.fetch!(flags, flag), do: Map.update!(counts, flag, &(&1 + 1)), else: counts
        end)

      _acc ->
        acc
    end
  end
end
