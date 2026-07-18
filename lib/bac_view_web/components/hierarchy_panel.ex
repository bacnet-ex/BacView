defmodule BacViewWeb.HierarchyPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.HierarchySplit
  alias BacViewWeb.DeviceTree
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.HierarchyExplorer
  alias BacViewWeb.HierarchyNodeIcon
  alias BacViewWeb.StatusFlagsIcons

  attr(:hierarchy_view, :string, required: true)
  attr(:hierarchy_source, :atom, default: :structured)
  attr(:hierarchy_split, :any, default: nil)
  attr(:name_hierarchy_form_open, :boolean, default: false)
  attr(:structured_hierarchy?, :boolean, default: false)
  attr(:hierarchy_view_paths, :map, required: true)
  attr(:hierarchy_root_path, :string, required: true)
  attr(:hierarchy_path_links, :list, default: [])
  attr(:device_id, :integer, required: true)
  attr(:roots, :list, required: true)
  attr(:entries, :list, default: [])
  attr(:empty_hierarchy?, :boolean, default: true)
  attr(:tree_roots, :list, default: [])
  attr(:tree_expanded, :any, default: MapSet.new())
  attr(:tree_search, :string, default: "")
  attr(:tree_match_count, :integer, default: 0)
  attr(:explorer_search, :string, default: "")
  attr(:explorer_match_count, :integer, default: 0)
  attr(:list_opts, :list, default: [])
  attr(:selected_keys, :any, default: MapSet.new())
  attr(:selectable_keys, :any, default: MapSet.new())
  attr(:subscribed_keys, :any, default: MapSet.new())
  attr(:flash_cells, :any, default: MapSet.new())

  def hierarchy_panel(assigns) do
    ~H"""
    <div class="space-y-5 min-w-0 w-full">
      <.name_hierarchy_banner
        :if={@hierarchy_source == :name && !@empty_hierarchy?}
        hierarchy_split={@hierarchy_split}
        structured_hierarchy?={@structured_hierarchy?}
        locale={@locale}
        locale_version={@locale_version}
      />

      <.name_hierarchy_builder
        :if={show_name_hierarchy_builder?(@empty_hierarchy?, @hierarchy_source, @name_hierarchy_form_open, @structured_hierarchy?)}
        empty_hierarchy?={@empty_hierarchy?}
        locale={@locale}
        locale_version={@locale_version}
      />

      <div :if={!@empty_hierarchy?} class="bac-tabs">
        <.link
          patch={@hierarchy_view_paths["explorer"]}
          class={["bac-tab", @hierarchy_view == "explorer" && "bac-tab-active"]}
          id="hierarchy-subtab-explorer"
        >
          <.icon name="hero-folder-open" class="size-4" />
          {t(@locale, @locale_version, "Ansicht")}
        </.link>
        <.link
          patch={@hierarchy_view_paths["tree"]}
          class={["bac-tab", @hierarchy_view == "tree" && "bac-tab-active"]}
          id="hierarchy-subtab-tree"
        >
          <.icon name="hero-list-bullet" class="size-4" />
          {t(@locale, @locale_version, "Liste")}
        </.link>
      </div>

      <div :if={@empty_hierarchy? && @hierarchy_source != :name} class="bac-hero py-16">
        <div class="bac-hero-icon">
          <.icon name="hero-folder-open" class="size-7" />
        </div>
        <p class="bac-hero-text">
          {t(@locale, @locale_version,
            "Keine Strukturansichten gefunden. Das Gerät verwendet eine flache Objektliste."
          )}
        </p>
        <.link
          patch={@hierarchy_view_paths["objects_fallback"]}
          class="bac-btn bac-btn-primary bac-btn-sm"
        >
          {t(@locale, @locale_version, "Alle Objekte anzeigen")}
        </.link>
      </div>

      <div :if={@empty_hierarchy? && @hierarchy_source == :name} class="bac-hero py-12">
        <p class="bac-hero-text">
          {t(@locale, @locale_version,
            "Mit den gewählten Aufteilungsregeln konnte keine Hierarchie erstellt werden."
          )}
        </p>
        <button
          type="button"
          id="clear-name-hierarchy-empty"
          phx-click="clear_name_hierarchy"
          class="bac-btn bac-btn-secondary bac-btn-sm"
        >
          {t(@locale, @locale_version, "Aufteilung zurücksetzen")}
        </button>
      </div>

      <div
        :if={@structured_hierarchy? && @hierarchy_source == :structured && !@name_hierarchy_form_open}
        class="flex justify-end"
      >
        <button
          type="button"
          id="open-name-hierarchy-form"
          phx-click="toggle_name_hierarchy_form"
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          <.icon name="hero-squares-2x2" class="size-4" />
          {t(@locale, @locale_version, "Hierarchie aus Objektnamen erstellen")}
        </button>
      </div>

      <.explorer_panel
        :if={!@empty_hierarchy? && @hierarchy_view == "explorer"}
        device_id={@device_id}
        entries={@entries}
        hierarchy_root_path={@hierarchy_root_path}
        hierarchy_path_links={@hierarchy_path_links}
        list_opts={@list_opts}
        search={@explorer_search}
        match_count={@explorer_match_count}
        selected_keys={@selected_keys}
        selectable_keys={@selectable_keys}
        subscribed_keys={@subscribed_keys}
        flash_cells={@flash_cells}
        locale={@locale}
        locale_version={@locale_version}
      />

      <DeviceTree.device_tree
        :if={!@empty_hierarchy? && @hierarchy_view == "tree"}
        device_id={@device_id}
        roots={@tree_roots}
        expanded={@tree_expanded}
        search={@tree_search}
        match_count={@tree_match_count}
        selected_keys={@selected_keys}
        selectable_keys={@selectable_keys}
        list_opts={@list_opts}
        locale={@locale}
        locale_version={@locale_version}
      />
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:entries, :list, required: true)
  attr(:hierarchy_root_path, :string, required: true)
  attr(:hierarchy_path_links, :list, default: [])
  attr(:list_opts, :list, default: [])
  attr(:search, :string, default: "")
  attr(:match_count, :integer, default: 0)
  attr(:selected_keys, :any, default: MapSet.new())
  attr(:selectable_keys, :any, default: MapSet.new())
  attr(:subscribed_keys, :any, default: MapSet.new())
  attr(:flash_cells, :any, default: MapSet.new())
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp explorer_panel(assigns) do
    ~H"""
    <div class="space-y-4 min-w-0 w-full" id="hierarchy-explorer">
      <div class="flex items-center gap-3">
        <input
          id="hierarchy-explorer-search"
          type="search"
          name="explorer_search"
          value={@search}
          placeholder={t(@locale, @locale_version, "Aktuellen Ordner durchsuchen… (-Begriff zum Ausschliessen)")}
          phx-keyup="search_hierarchy_explorer"
          phx-debounce="200"
          class="bac-input bac-input-sm max-w-md"
        />
        <span :if={@search != ""} class="text-xs bac-text-faint whitespace-nowrap">
          {t(@locale, @locale_version, "%{count} Treffer", count: @match_count)}
        </span>
      </div>

      <nav
        :if={@hierarchy_path_links != []}
        class="flex flex-wrap items-center gap-x-1 gap-y-2 text-sm"
        aria-label={t(@locale, @locale_version, "Pfad")}
      >
        <.link
          patch={@hierarchy_root_path}
          class="bac-btn bac-btn-ghost bac-btn-xs"
          id="hierarchy-breadcrumb-root"
        >
          <.icon name="hero-home" class="size-3.5" />
          {t(@locale, @locale_version, "Wurzel")}
        </.link>
        <%= for {label, _path, patch} <- @hierarchy_path_links do %>
          <.icon name="hero-chevron-right" class="size-3 bac-text-faint" />
          <.link
            patch={patch}
            class="bac-btn bac-btn-ghost bac-btn-xs h-auto max-w-full items-start whitespace-normal break-words text-left"
          >
            {label}
          </.link>
        <% end %>
      </nav>

      <p :if={@entries == [] && @search != ""} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Keine Treffer in diesem Ordner.")}
      </p>

      <p :if={@entries == [] && @search == ""} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Dieser Ordner ist leer.")}
      </p>

      <div :if={@entries != []} class="bac-table-wrap">
        <table class="bac-table" id="hierarchy-explorer-table">
          <colgroup>
            <col class="w-10" />
            <col />
            <col class="w-36" />
            <col class="w-32" />
          </colgroup>
          <thead>
            <tr>
              <th class="w-10">
                <input
                  id="hierarchy-select-all"
                  type="checkbox"
                  checked={all_visible_selected?(@selected_keys, @entries, @selectable_keys)}
                  phx-click="toggle_select_all_hierarchy"
                  class="bac-checkbox"
                  aria-label={t(@locale, @locale_version, "Alle sichtbaren Einträge auswählen")}
                />
              </th>
              <th>{t(@locale, @locale_version, "Name")}</th>
              <th class="w-36">{t(@locale, @locale_version, "Status")}</th>
              <th class="text-right">{t(@locale, @locale_version, "Present Value")}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={entry <- @entries}
              id={"hierarchy-entry-#{entry.type}-#{entry.instance}"}
              class={entry_row_class(@flash_cells, entry)}
            >
              <td :if={entry.kind == :folder} class="w-10 align-top">
                <span
                  :if={folder_selectable?(entry)}
                  class="cursor-pointer"
                  phx-click="toggle_object_selection"
                  phx-value-type={entry.type}
                  phx-value-instance={entry.instance}
                >
                  <input
                    type="checkbox"
                    checked={folder_selected?(@selected_keys, entry)}
                    class="bac-checkbox pointer-events-none"
                    aria-label={t(@locale, @locale_version, "Ordner und Unterobjekte auswählen")}
                  />
                </span>
              </td>

              <td :if={entry.kind == :folder} class="align-top min-w-0 p-0">
                <.link
                  patch={folder_patch(@device_id, @hierarchy_path_links, entry, @list_opts)}
                  class="flex items-center gap-3 px-3 py-3 hover:bg-[var(--bac-surface-hover)] transition-colors"
                  id={"hierarchy-folder-#{entry.type}-#{entry.instance}"}
                >
                  <span title={HierarchyNodeIcon.tooltip(entry.node_subtype)} class="inline-flex">
                    <.icon
                      name={HierarchyNodeIcon.name(entry.node_type)}
                      class={HierarchyNodeIcon.icon_class(entry.node_type, "size-5")}
                    />
                  </span>
                  <div class="min-w-0 flex-1">
                    <p :if={entry.annotation} class="text-xs bac-text-faint truncate">
                      {entry.annotation}
                    </p>
                    <p class="text-sm font-medium truncate">{entry.name}</p>
                    <p class="text-xs text-[var(--bac-text-muted)] truncate">
                      {entry.description || "-"}
                    </p>
                  </div>
                  <span :if={entry.child_count > 0} class="bac-badge bac-badge-sm shrink-0">
                    {entry.child_count}
                  </span>
                  <span :if={entry.cycle} class="bac-badge bac-badge-sm bac-badge-warning shrink-0">
                    {t(@locale, @locale_version, "Zyklus")}
                  </span>
                  <.icon name="hero-chevron-right" class="size-4 bac-text-faint shrink-0" />
                </.link>
              </td>

              <td :if={entry.kind == :folder} class="align-top w-36">
                <StatusFlagsIcons.status_flags_icons
                  mode={:counts}
                  counts={entry.status_flag_counts}
                  locale={@locale}
                  locale_version={@locale_version}
                />
              </td>

              <td :if={entry.kind == :folder} class="align-top"></td>

              <td :if={entry.kind == :object} class="w-10 align-top">
                <span
                  :if={selectable?(@selectable_keys, entry)}
                  class="cursor-pointer"
                  phx-click="toggle_object_selection"
                  phx-value-type={entry.type}
                  phx-value-instance={entry.instance}
                >
                  <input
                    type="checkbox"
                    checked={selected?(@selected_keys, entry)}
                    class="bac-checkbox pointer-events-none"
                    aria-label={t(@locale, @locale_version, "Objekt auswählen")}
                  />
                </span>
              </td>

              <td :if={entry.kind == :object} class="align-top min-w-0">
                <.link
                  navigate={object_path(@device_id, entry, @list_opts)}
                  class="block min-w-0 py-1 group"
                >
                  <p class="text-xs bac-text-faint truncate">
                    {entry.annotation || "-"}
                  </p>
                  <p class="text-sm font-medium text-[var(--bac-text)] group-hover:text-[var(--bac-accent)] flex items-center gap-2 min-w-0">
                    <span class="truncate">{entry.name}</span>
                    <span
                      :if={live?(@subscribed_keys, entry)}
                      class="bac-badge bac-badge-sm bac-badge-success shrink-0"
                    >
                      {t(@locale, @locale_version, "Live")}
                    </span>
                  </p>
                  <p class="text-xs text-[var(--bac-text-muted)] truncate">
                    {entry.description || "-"}
                  </p>
                </.link>
              </td>

              <td :if={entry.kind == :object} class="align-top w-36">
                <StatusFlagsIcons.status_flags_icons
                  flags={entry.status_flags}
                  locale={@locale}
                  locale_version={@locale_version}
                />
              </td>

              <td
                :if={entry.kind == :object}
                class={[
                  "align-top bac-mono text-right whitespace-nowrap",
                  entry.writable && "cursor-pointer"
                ]}
                phx-click={if entry.writable, do: "open_write_modal"}
                phx-value-type={if entry.writable, do: entry.type}
                phx-value-instance={if entry.writable, do: entry.instance}
                title={if entry.writable, do: t(@locale, @locale_version, "Klicken zum Schreiben")}
              >
                <span class={entry.writable && "bac-cell-writable"}>
                  {present_value_label(entry)}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp folder_patch(device_id, path_links, entry, list_opts) do
    path =
      case path_links do
        [] ->
          [{entry.type, entry.instance}]

        _device_id ->
          {_label, last_path, _patch} = List.last(path_links)
          HierarchyExplorer.append_segment(last_path, {entry.type, entry.instance})
      end

    hierarchy_device_path(device_id, list_opts, path)
  end

  defp hierarchy_device_path(device_id, list_opts, path) do
    url_opts =
      list_opts
      |> Keyword.delete(:device_id)
      |> Keyword.put(:tab, "hierarchy")
      |> Keyword.put(:hierarchy_view, "explorer")
      |> Keyword.put(:hierarchy_path, path)

    DeviceUrl.device_path(device_id, url_opts)
  end

  defp object_path(device_id, entry, list_opts) do
    url_opts =
      list_opts
      |> Keyword.delete(:device_id)
      |> Keyword.put(:tab, "hierarchy")
      |> Keyword.put(:hierarchy_view, "explorer")

    DeviceUrl.object_path(device_id, entry.type, entry.instance, url_opts)
  end

  defp selected?(keys, entry), do: MapSet.member?(keys, {entry.type, entry.instance})
  defp selectable?(keys, entry), do: MapSet.member?(keys, {entry.type, entry.instance})

  defp folder_selectable?(%{selectable_descendant_keys: keys}),
    do: keys != MapSet.new()

  defp folder_selected?(selected_keys, entry),
    do: HierarchyExplorer.folder_selected?(selected_keys, entry.selectable_descendant_keys)

  defp all_visible_selected?(selected_keys, entries, selectable_keys) do
    visible = HierarchyExplorer.visible_selection_keys(entries, selectable_keys)
    HierarchyExplorer.folder_selected?(selected_keys, visible)
  end

  defp live?(keys, entry),
    do: MapSet.member?(keys, {entry.type, entry.instance, :present_value})

  defp entry_row_class(cells, %{kind: :object, type: type, instance: instance}) do
    if MapSet.member?(cells, {type, instance}), do: "bac-row-flash", else: nil
  end

  defp entry_row_class(_cells, _entry), do: nil

  defp present_value_label(%{commandable: true, active_priority: priority} = entry)
       when not is_nil(priority) do
    "#{entry.present_value_formatted} (#{priority})"
  end

  defp present_value_label(entry), do: entry.present_value_formatted

  attr(:hierarchy_split, :any, required: true)
  attr(:structured_hierarchy?, :boolean, default: false)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp name_hierarchy_banner(assigns) do
    ~H"""
    <div
      id="name-hierarchy-banner"
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[var(--bac-border)] bg-[var(--bac-surface)] px-4 py-3"
    >
      <div class="min-w-0">
        <p class="text-sm font-medium text-[var(--bac-text)]">
          {t(@locale, @locale_version, "Hierarchie aus Objektnamen")}
        </p>
        <p class="text-xs bac-text-muted truncate">
          {split_summary(@locale, @locale_version, @hierarchy_split)}
        </p>
      </div>
      <button
        type="button"
        id="clear-name-hierarchy"
        phx-click="clear_name_hierarchy"
        class="bac-btn bac-btn-secondary bac-btn-sm shrink-0"
      >
        <%= if @structured_hierarchy? do %>
          {t(@locale, @locale_version, "Strukturansichten verwenden")}
        <% else %>
          {t(@locale, @locale_version, "Aufteilung zurücksetzen")}
        <% end %>
      </button>
    </div>
    """
  end

  attr(:empty_hierarchy?, :boolean, required: true)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp name_hierarchy_builder(assigns) do
    ~H"""
    <div
      id="name-hierarchy-builder"
      class={[
        "rounded-xl border border-[var(--bac-border)] bg-[var(--bac-surface)] p-4 space-y-4",
        @empty_hierarchy? && "max-w-2xl mx-auto"
      ]}
    >
      <div class="space-y-1">
        <h3 class="text-sm font-semibold text-[var(--bac-text)]">
          {t(@locale, @locale_version, "Hierarchie aus Objektnamen erstellen")}
        </h3>
        <p class="text-xs bac-text-muted">
          {t(@locale, @locale_version,
            "Teilt Objektnamen nach Trennzeichen oder festen Zeichenpositionen in Ordner auf."
          )}
        </p>
      </div>

      <form id="name-hierarchy-form" phx-submit="build_name_hierarchy" class="space-y-5">
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-1.5 min-w-0">
            <label for="name-hierarchy-mode" class="block text-xs font-medium bac-text-muted">
              {t(@locale, @locale_version, "Aufteilungsmodus")}
            </label>
            <select
              id="name-hierarchy-mode"
              name="name_hierarchy[mode]"
              class="bac-input bac-input-sm w-full"
            >
              <option value="delimiter">{t(@locale, @locale_version, "Trennzeichen")}</option>
              <option value="positions">{t(@locale, @locale_version, "Zeichenpositionen")}</option>
            </select>
          </div>

          <div class="space-y-1.5 min-w-0">
            <label for="name-hierarchy-delimiter" class="block text-xs font-medium bac-text-muted">
              {t(@locale, @locale_version, "Trennzeichen")}
            </label>
            <select
              id="name-hierarchy-delimiter"
              name="name_hierarchy[delimiter]"
              class="bac-input bac-input-sm w-full"
            >
              <%= for %{id: id} <- HierarchySplit.delimiter_options() do %>
                <option value={id}>{delimiter_option_label(@locale, @locale_version, id)}</option>
              <% end %>
            </select>
          </div>
        </div>

        <div class="space-y-1.5">
          <label for="name-hierarchy-positions" class="block text-xs font-medium bac-text-muted">
            {t(@locale, @locale_version, "Positionen (kommagetrennt)")}
          </label>
          <input
            id="name-hierarchy-positions"
            type="text"
            name="name_hierarchy[positions]"
            placeholder="10, 5, 8"
            class="bac-input bac-input-sm w-full"
          />
          <p class="text-xs bac-text-faint leading-relaxed pt-0.5">
            {t(@locale, @locale_version,
              "Nur bei Modus „Zeichenpositionen“. Beispiel: 10, 5, 8 teilt nach 10, dann 5 und danach 8 Zeichen."
            )}
          </p>
        </div>

        <div class="mt-2 border-t border-[var(--bac-border)] pt-5">
          <div class="flex flex-wrap items-center gap-2">
            <button type="submit" id="build-name-hierarchy" class="bac-btn bac-btn-primary bac-btn-sm">
              <.icon name="hero-folder-plus" class="size-4" />
              {t(@locale, @locale_version, "Hierarchie erstellen")}
            </button>
            <button
              :if={!@empty_hierarchy?}
              type="button"
              id="cancel-name-hierarchy-form"
              phx-click="toggle_name_hierarchy_form"
              class="bac-btn bac-btn-ghost bac-btn-sm"
            >
              {t(@locale, @locale_version, "Abbrechen")}
            </button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp show_name_hierarchy_builder?(
         empty_hierarchy?,
         hierarchy_source,
         form_open,
         structured_hierarchy?
       ) do
    cond do
      hierarchy_source == :name && empty_hierarchy? -> true
      empty_hierarchy? && not structured_hierarchy? -> true
      form_open -> true
      true -> false
    end
  end

  defp split_summary(locale, locale_version, {:delimiter, delim}) do
    t(locale, locale_version, "Trennzeichen: %{delimiter}",
      delimiter: delimiter_summary_label(locale, locale_version, delim)
    )
  end

  defp split_summary(locale, locale_version, {:positions, positions}) do
    t(locale, locale_version, "Positionen: %{positions}", positions: Enum.join(positions, ", "))
  end

  defp split_summary(_locale, _locale_version, _split), do: ""

  defp delimiter_summary_label(locale, locale_version, :all_special),
    do: t(locale, locale_version, "Alle Sonderzeichen")

  defp delimiter_summary_label(locale, locale_version, " "),
    do: t(locale, locale_version, "Leerzeichen")

  defp delimiter_summary_label(locale, locale_version, "_"),
    do: t(locale, locale_version, "Unterstrich (_)")

  defp delimiter_summary_label(locale, locale_version, "."),
    do: t(locale, locale_version, "Punkt (.)")

  defp delimiter_summary_label(locale, locale_version, ":"),
    do: t(locale, locale_version, "Doppelpunkt (:)")

  defp delimiter_summary_label(locale, locale_version, "-"),
    do: t(locale, locale_version, "Bindestrich (-)")

  defp delimiter_summary_label(locale, locale_version, "/"),
    do: t(locale, locale_version, "Schrägstrich (/)")

  defp delimiter_summary_label(_locale, _locale_version, delim),
    do: HierarchySplit.delimiter_label(delim)

  defp delimiter_option_label(locale, locale_version, "all"),
    do: t(locale, locale_version, "Alle Sonderzeichen")

  defp delimiter_option_label(locale, locale_version, "space"),
    do: t(locale, locale_version, "Leerzeichen")

  defp delimiter_option_label(locale, locale_version, "_"),
    do: t(locale, locale_version, "Unterstrich (_)")

  defp delimiter_option_label(locale, locale_version, "."),
    do: t(locale, locale_version, "Punkt (.)")

  defp delimiter_option_label(locale, locale_version, ":"),
    do: t(locale, locale_version, "Doppelpunkt (:)")

  defp delimiter_option_label(locale, locale_version, "-"),
    do: t(locale, locale_version, "Bindestrich (-)")

  defp delimiter_option_label(locale, locale_version, "/"),
    do: t(locale, locale_version, "Schrägstrich (/)")

  defp delimiter_option_label(locale, locale_version, id) do
    char = HierarchySplit.delimiter_from_id(id) || id

    t(locale, locale_version, "Sonderzeichen „%{char}“", char: char)
  end
end
