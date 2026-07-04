defmodule BacViewWeb.LocaleRefresh do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias BacView.BACnet.HierarchyBuilder
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter

  @spec refresh_socket(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_socket(socket) do
    socket
    |> refresh_objects_assign()
    |> refresh_object_assign()
    |> refresh_properties_assign()
    |> refresh_hierarchy_assign()
    |> refresh_write_modal_assign()
    |> assign(:locale_version, locale_version(socket) + 1)
  end

  @spec refresh_objects([map()]) :: [map()]
  def refresh_objects(objects) when is_list(objects), do: Enum.map(objects, &refresh_object/1)
  def refresh_objects(_objects), do: []

  @spec refresh_object(map() | nil) :: map() | nil
  def refresh_object(%{} = object) do
    type = Map.get(object, :type)

    object
    |> Map.put(:type_label, ObjectTypes.short_label(type))
    |> refresh_present_value_formatted()
  end

  def refresh_object(object), do: object

  defp refresh_present_value_formatted(%{present_value: value} = object) when is_map(object) do
    Map.put(
      object,
      :present_value_formatted,
      PropertyFormatter.format_present_value(value, object)
    )
  end

  defp refresh_present_value_formatted(object), do: object

  @spec refresh_properties([map()], keyword()) :: [map()]
  def refresh_properties(properties, opts \\ []) when is_list(properties) do
    Enum.map(properties, &PropertyEnumeration.relocalize_property(&1, opts))
  end

  @spec refresh_hierarchy_nodes(list()) :: list()
  def refresh_hierarchy_nodes(nodes) when is_list(nodes) do
    Enum.map(nodes, &refresh_hierarchy_node/1)
  end

  def refresh_hierarchy_nodes(_nodes), do: []

  defp refresh_hierarchy_node(%{children: children} = node) when is_map(node) do
    node
    |> Map.put(:type_label, ObjectTypes.label(Map.get(node, :type)))
    |> Map.put(:children, refresh_hierarchy_nodes(children))
  end

  defp refresh_hierarchy_node(node), do: node

  defp refresh_objects_assign(socket) do
    case socket.assigns do
      %{objects: objects} when is_list(objects) ->
        assign(socket, :objects, refresh_objects(objects))

      _socket ->
        socket
    end
  end

  defp refresh_object_assign(socket) do
    case socket.assigns do
      %{object: %{} = object} ->
        assign(socket, :object, refresh_object(object))

      _socket ->
        socket
    end
  end

  defp refresh_properties_assign(socket) do
    case socket.assigns do
      %{properties: properties} when is_list(properties) ->
        units = socket.assigns[:object] && Map.get(socket.assigns.object, :units)
        assign(socket, :properties, refresh_properties(properties, units: units))

      _socket ->
        socket
    end
  end

  defp refresh_hierarchy_assign(socket) do
    case socket.assigns do
      %{hierarchy: %{roots: roots} = hierarchy} when is_list(roots) ->
        refreshed_roots = refresh_hierarchy_nodes(roots)
        hierarchy = %{hierarchy | roots: refreshed_roots}
        search = Map.get(socket.assigns, :tree_search, "")
        {tree_roots, count} = HierarchyBuilder.filter_tree(refreshed_roots, search)

        socket
        |> assign(:hierarchy, hierarchy)
        |> assign(:tree_roots, tree_roots)
        |> assign(:tree_match_count, count)

      _socket ->
        socket
    end
  end

  defp refresh_write_modal_assign(socket) do
    case socket.assigns do
      %{write_modal: %{} = object} ->
        assign(socket, :write_modal, refresh_object(object))

      _socket ->
        socket
    end
  end

  defp locale_version(socket), do: Map.get(socket.assigns, :locale_version, 0)
end
