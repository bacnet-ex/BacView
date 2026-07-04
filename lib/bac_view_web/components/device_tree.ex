defmodule BacViewWeb.DeviceTree do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.HierarchyExplorer
  alias BacViewWeb.HierarchyNodeIcon
  alias BacViewWeb.ObjectTypeIcon

  attr(:device_id, :integer, required: true)
  attr(:roots, :list, required: true)
  attr(:expanded, :any, required: true)
  attr(:search, :string, default: "")
  attr(:match_count, :integer, default: 0)
  attr(:selected_keys, :any, default: MapSet.new())
  attr(:selectable_keys, :any, default: MapSet.new())
  attr(:list_opts, :list, default: [])

  def device_tree(assigns) do
    ~H"""
    <div class="space-y-4" id="device-tree">
      <div class="flex items-center gap-3">
        <input
          id="tree-search"
          type="search"
          name="tree_search"
          value={@search}
          placeholder={t(@locale, @locale_version, "Hierarchie durchsuchen… (-Begriff zum Ausschließen)")}
          phx-keyup="search_tree"
          phx-debounce="200"
          class="bac-input bac-input-sm max-w-md"
        />
        <span :if={@search != ""} class="text-xs bac-text-faint whitespace-nowrap">
          {t(@locale, @locale_version, "%{count} Treffer", count: @match_count)}
        </span>
        <label class="inline-flex items-center gap-2 ml-auto text-xs bac-text-muted cursor-pointer">
          <input
            id="hierarchy-tree-select-all"
            type="checkbox"
            checked={all_visible_selected?(@roots, @selected_keys, @selectable_keys)}
            phx-click="toggle_select_all_hierarchy"
            class="bac-checkbox"
            aria-label={t(@locale, @locale_version, "Alle sichtbaren Einträge auswählen")}
          />
          {t(@locale, @locale_version, "Alle auswählen")}
        </label>
      </div>

      <ul class="space-y-0.5" role="tree">
        <.tree_node
          :for={node <- @roots}
          device_id={@device_id}
          node={node}
          expanded={@expanded}
          selected_keys={@selected_keys}
          selectable_keys={@selectable_keys}
          depth={0}
          locale={@locale}
          locale_version={@locale_version}
        />
      </ul>
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:node, :map, required: true)
  attr(:expanded, :any, required: true)
  attr(:selected_keys, :any, required: true)
  attr(:selectable_keys, :any, required: true)
  attr(:list_opts, :list, default: [])
  attr(:depth, :integer, default: 0)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp tree_node(assigns) do
    node_id = BacView.BACnet.HierarchyNode.id(assigns.node)
    has_children = assigns.node.child_count > 0
    node_expanded = MapSet.member?(assigns.expanded, node_id)
    is_sv = assigns.node.type == :structured_view
    selectable = hierarchy_selectable?(assigns.selectable_keys, assigns.node)
    selected = hierarchy_selected?(assigns.selected_keys, assigns.selectable_keys, assigns.node)

    assigns =
      assigns
      |> assign(:node_id, node_id)
      |> assign(:has_children, has_children)
      |> assign(:node_expanded, node_expanded)
      |> assign(:is_sv, is_sv)
      |> assign(:selectable, selectable)
      |> assign(:selected, selected)

    ~H"""
    <li role="treeitem" aria-expanded={@has_children && @node_expanded}>
      <div
        class={[
          "bac-tree-node group",
          @selected && "bac-tree-node-selected"
        ]}
        style={"padding-left: #{@depth * 1.25 + 0.5}rem"}
      >
        <span
          :if={@selectable}
          class="shrink-0 cursor-pointer"
          phx-click="toggle_object_selection"
          phx-value-type={@node.type}
          phx-value-instance={@node.instance}
        >
          <input
            type="checkbox"
            checked={@selected}
            class="bac-checkbox pointer-events-none"
            aria-label={t(@locale, @locale_version, "Objekt auswählen")}
          />
        </span>
        <span :if={!@selectable} class="w-4 shrink-0" />

        <button
          :if={@has_children}
          type="button"
          phx-click="toggle_tree_node"
          phx-value-id={@node_id}
          class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
          aria-label={t(@locale, @locale_version, "Aufklappen")}
        >
          <.icon
            name={if @node_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="size-3.5"
          />
        </button>
        <span :if={!@has_children} class="w-8 shrink-0" />

        <button
          type="button"
          phx-click={JS.navigate(node_object_path(@device_id, @node, @list_opts))}
          class="flex items-center gap-2 flex-1 min-w-0 text-left"
        >
          <span :if={@is_sv} title={HierarchyNodeIcon.tooltip(@node.node_subtype)} class="inline-flex">
            <.icon
              name={HierarchyNodeIcon.name(@node.node_type)}
              class={HierarchyNodeIcon.icon_class(@node.node_type)}
            />
          </span>
          <.icon
            :if={!@is_sv}
            name={ObjectTypeIcon.name(@node.type)}
            class="size-4 shrink-0 text-[var(--bac-accent)]"
          />
          <span class="truncate text-sm font-medium text-[var(--bac-text)]">
            {@node.name || "#{@node.type}:#{@node.instance}"}
          </span>
          <span :if={@node.annotation} class="truncate text-xs bac-text-faint hidden sm:inline">
            {@node.annotation}
          </span>
          <span :if={@is_sv && @has_children} class="bac-badge bac-badge-sm shrink-0">
            {@node.child_count}
          </span>
          <span :if={@node.cycle} class="bac-badge bac-badge-sm bac-badge-warning shrink-0">
            {t(@locale, @locale_version, "Zyklus")}
          </span>
        </button>

        <button
          type="button"
          phx-click="reveal_in_flat_list"
          phx-value-type={@node.type}
          phx-value-instance={@node.instance}
          class="bac-btn bac-btn-ghost bac-btn-xs opacity-0 group-hover:opacity-100 shrink-0"
          title={t(@locale, @locale_version, "In flacher Liste anzeigen")}
        >
          <.icon name="hero-list-bullet" class="size-3.5" />
        </button>
      </div>

      <ul :if={@has_children && @node_expanded} role="group">
        <.tree_node
          :for={child <- @node.children}
          device_id={@device_id}
          node={child}
          expanded={@expanded}
          selected_keys={@selected_keys}
          selectable_keys={@selectable_keys}
          list_opts={@list_opts}
          depth={@depth + 1}
          locale={@locale}
          locale_version={@locale_version}
        />
      </ul>
    </li>
    """
  end

  defp hierarchy_selectable?(keys, %{type: :structured_view} = node),
    do: HierarchyExplorer.descendant_selectable_keys(node, keys) != MapSet.new()

  defp hierarchy_selectable?(keys, node),
    do: MapSet.member?(keys, {node.type, node.instance})

  defp hierarchy_selected?(selected_keys, selectable_keys, %{type: :structured_view} = node) do
    HierarchyExplorer.folder_selected?(
      selected_keys,
      HierarchyExplorer.descendant_selectable_keys(node, selectable_keys)
    )
  end

  defp hierarchy_selected?(selected_keys, _selectable_keys, node),
    do: MapSet.member?(selected_keys, {node.type, node.instance})

  defp all_visible_selected?(roots, selected_keys, selectable_keys) do
    visible = HierarchyExplorer.tree_visible_selection_keys(roots, selectable_keys)
    HierarchyExplorer.folder_selected?(selected_keys, visible)
  end

  defp node_object_path(device_id, node, list_opts) do
    DeviceUrl.object_path(device_id, node.type, node.instance, list_opts)
  end
end
