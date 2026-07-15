defmodule BacViewWeb.ObjectTable do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.NaturalSort
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.SearchQuery
  alias BacViewWeb.StatusFlagsIcons

  @sort_columns ~w(object_id name description type present_value updated_at)
  @status_filter_flags [:in_alarm, :fault, :overridden, :out_of_service, :none]

  attr(:device_id, :integer, required: true)
  attr(:objects, :list, required: true)
  attr(:search, :string, default: "")
  attr(:type_filter, :list, default: [])
  attr(:type_filter_open, :boolean, default: false)
  attr(:status_filter, :list, default: [])
  attr(:status_filter_open, :boolean, default: false)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:subscribed_keys, :any, default: MapSet.new())
  attr(:selected_keys, :any, default: MapSet.new())
  attr(:flash_cells, :any, default: MapSet.new())

  def object_table(assigns) do
    available_types = available_types(assigns.objects)
    available_statuses = available_status_flags(assigns.objects)

    assigns =
      assigns
      |> assign(:available_types, available_types)
      |> assign(:available_statuses, available_statuses)
      |> assign(:list_opts, %{
        search: assigns.search,
        type_filter: assigns.type_filter,
        status_filter: assigns.status_filter,
        sort_by: assigns.sort_by,
        sort_dir: assigns.sort_dir
      })
      |> assign(
        :filtered,
        list_objects(
          assigns.objects,
          assigns.search,
          assigns.type_filter,
          assigns.status_filter,
          assigns.sort_by,
          assigns.sort_dir
        )
      )

    ~H"""
    <div class="space-y-4">
      <input
        id="object-search"
        type="search"
        name="search"
        value={@search}
        placeholder={t(@locale, @locale_version, "Objekte suchen… (-Begriff zum Ausschliessen)")}
        phx-keyup="search_objects"
        phx-debounce="200"
        class="bac-input bac-input-sm max-w-md"
      />

      <div
        :if={@type_filter_open}
        id="object-type-filter-menu"
        phx-hook="FilterMenu"
        data-trigger-id="object-type-filter-toggle"
        data-close-event="close_type_filter_panel"
        class="bac-filter-menu"
      >
        <div class="bac-filter-menu-header">
          <p class="text-xs font-semibold text-[var(--bac-text)]">
            {t(@locale, @locale_version, "Objekttypen")}
          </p>
          <button
            :if={type_filter_active?(@type_filter)}
            type="button"
            phx-click="reset_object_type_filter"
            class="bac-btn bac-btn-ghost bac-btn-xs"
          >
            {t(@locale, @locale_version, "Alle")}
          </button>
        </div>
        <ul class="bac-filter-menu-list">
          <li :for={entry <- @available_types} class="bac-filter-menu-item">
            <label class="flex items-center gap-2 flex-1 min-w-0 cursor-pointer">
              <input
                type="checkbox"
                checked={type_checked?(@type_filter, @available_types, entry.type)}
                phx-click="toggle_object_type"
                phx-value-type={entry.type}
                class="bac-checkbox shrink-0"
              />
              <span class="truncate text-sm text-[var(--bac-text)]">{entry.label}</span>
              <span class="bac-badge bac-badge-xs bac-text-faint ml-auto shrink-0">
                {entry.count}
              </span>
            </label>
            <button
              type="button"
              phx-click="filter_object_type_only"
              phx-value-type={entry.type}
              class="bac-btn bac-btn-ghost bac-btn-xs shrink-0"
              title={t(@locale, @locale_version, "Nur diesen Typ anzeigen")}
            >
              {t(@locale, @locale_version, "Nur")}
            </button>
          </li>
        </ul>
      </div>

      <div
        :if={@status_filter_open}
        id="object-status-filter-menu"
        phx-hook="FilterMenu"
        data-trigger-id="object-status-filter-toggle"
        data-close-event="close_status_filter_panel"
        class="bac-filter-menu"
      >
        <div class="bac-filter-menu-header">
          <p class="text-xs font-semibold text-[var(--bac-text)]">
            {t(@locale, @locale_version, "Status-Flags")}
          </p>
          <button
            :if={status_filter_active?(@status_filter)}
            type="button"
            phx-click="reset_object_status_filter"
            class="bac-btn bac-btn-ghost bac-btn-xs"
          >
            {t(@locale, @locale_version, "Alle")}
          </button>
        </div>
        <ul class="bac-filter-menu-list">
          <li :for={entry <- @available_statuses} class="bac-filter-menu-item">
            <label class="flex items-center gap-2 flex-1 min-w-0 cursor-pointer">
              <input
                type="checkbox"
                checked={status_checked?(@status_filter, @available_statuses, entry.flag)}
                phx-click="toggle_object_status"
                phx-value-status={entry.flag}
                class="bac-checkbox shrink-0"
              />
              <span class={["inline-flex shrink-0", StatusFlagsIcons.flag_class(entry.flag)]}>
                <.icon name={StatusFlagsIcons.icon_name(entry.flag)} class="size-4" />
              </span>
              <span class="truncate text-sm text-[var(--bac-text)]">
                {StatusFlagsIcons.flag_label(entry.flag, @locale, @locale_version)}
              </span>
              <span class="bac-badge bac-badge-xs bac-text-faint ml-auto shrink-0">
                {entry.count}
              </span>
            </label>
            <button
              type="button"
              phx-click="filter_object_status_only"
              phx-value-status={entry.flag}
              class="bac-btn bac-btn-ghost bac-btn-xs shrink-0"
              title={t(@locale, @locale_version, "Nur diesen Status anzeigen")}
            >
              {t(@locale, @locale_version, "Nur")}
            </button>
          </li>
        </ul>
      </div>

      <div class="bac-table-wrap">
        <table class="bac-table" id="object-table">
          <thead>
            <tr>
              <th class="w-10">
                <input
                  id="object-select-all"
                  type="checkbox"
                  checked={all_selected?(@selected_keys, @filtered)}
                  phx-click="toggle_select_all_objects"
                  class="bac-checkbox"
                  aria-label={t(@locale, @locale_version, "Alle Objekte auswählen")}
                />
              </th>
              <th>
                <.sort_header
                  column="object_id"
                  label={t(@locale, @locale_version, "Objekt-ID")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <.sort_header
                  column="name"
                  label={t(@locale, @locale_version, "Name")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <.sort_header
                  column="description"
                  label={t(@locale, @locale_version, "Beschreibung")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <div class="inline-flex items-center gap-1.5">
                  <.sort_header
                    column="type"
                    label={t(@locale, @locale_version, "Typ")}
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <button
                    id="object-type-filter-toggle"
                    type="button"
                    phx-click="toggle_type_filter_panel"
                    class={[
                      "bac-btn bac-btn-ghost bac-btn-xs inline-flex items-center gap-1",
                      type_filter_active?(@type_filter) && "text-[var(--bac-accent)]"
                    ]}
                    aria-expanded={to_string(@type_filter_open)}
                    aria-controls="object-type-filter-menu"
                    title={t(@locale, @locale_version, "Nach Typ filtern")}
                  >
                    <.icon name="hero-funnel" class="size-3.5" />
                    <span :if={type_filter_active?(@type_filter)} class="bac-badge bac-badge-xs bac-badge-accent">
                      {length(@type_filter)}
                    </span>
                  </button>
                </div>
              </th>
              <th class="w-28">
                <div class="inline-flex items-center gap-1.5">
                  <span class="bac-sort-header">
                    {t(@locale, @locale_version, "Status")}
                  </span>
                  <button
                    id="object-status-filter-toggle"
                    type="button"
                    phx-click="toggle_status_filter_panel"
                    class={[
                      "bac-btn bac-btn-ghost bac-btn-xs inline-flex items-center gap-1",
                      status_filter_active?(@status_filter) && "text-[var(--bac-accent)]"
                    ]}
                    aria-expanded={to_string(@status_filter_open)}
                    aria-controls="object-status-filter-menu"
                    title={t(@locale, @locale_version, "Nach Status filtern")}
                  >
                    <.icon name="hero-funnel" class="size-3.5" />
                    <span
                      :if={status_filter_active?(@status_filter)}
                      class="bac-badge bac-badge-xs bac-badge-accent"
                    >
                      {length(@status_filter)}
                    </span>
                  </button>
                </div>
              </th>
              <th>
                <.sort_header
                  column="present_value"
                  label={t(@locale, @locale_version, "Present_Value")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <.sort_header
                  column="updated_at"
                  label={t(@locale, @locale_version, "Aktualisiert")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
            </tr>
          </thead>
          <tbody id="object-table-body">
            <tr
              :for={obj <- @filtered}
              id={"object-#{obj.type}-#{obj.instance}"}
              class={[
                flash_class(@flash_cells, obj),
                selected?(@selected_keys, obj) && "bac-row-selected"
              ]}
            >
              <td
                phx-click="toggle_object_selection"
                phx-value-type={obj.type}
                phx-value-instance={obj.instance}
                class="cursor-pointer"
              >
                <input
                  type="checkbox"
                  checked={selected?(@selected_keys, obj)}
                  class="bac-checkbox pointer-events-none"
                  aria-label={t(@locale, @locale_version, "Objekt auswählen")}
                />
              </td>
              <td
                class="bac-mono bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, obj, @list_opts))}
              >
                <span class="flex items-center gap-2">
                  {obj.type}:{obj.instance}
                  <span :if={live?(@subscribed_keys, obj)} class="bac-badge bac-badge-sm bac-badge-success">
                    {t(@locale, @locale_version, "Live")}
                  </span>
                  <.icon name="hero-chevron-right" class="size-3.5 bac-text-faint ml-auto" />
                </span>
              </td>
              <td
                class="text-[var(--bac-text)] bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, obj, @list_opts))}
              >
                {obj.name || "-"}
              </td>
              <td
                class="text-[var(--bac-text-muted)] max-w-xs truncate bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, obj, @list_opts))}
                title={object_description(obj)}
              >
                {object_description(obj) || "-"}
              </td>
              <td>
                <button
                  type="button"
                  phx-click="filter_object_type_only"
                  phx-value-type={obj.type}
                  class="bac-badge bac-badge-sm hover:ring-1 hover:ring-[var(--bac-accent)] transition-shadow cursor-pointer"
                  title={t(@locale, @locale_version, "Nur %{type} anzeigen", type: ObjectTypes.short_label(obj.type))}
                >
                  {ObjectTypes.short_label(obj.type)}
                </button>
              </td>
              <td>
                <StatusFlagsIcons.status_flags_icons
                  flags={Map.get(obj, :status_flags)}
                  locale={@locale}
                  locale_version={@locale_version}
                />
              </td>
              <td
                class={[
                  "bac-mono",
                  writable?(obj) && "bac-cell-writable"
                ]}
                phx-click={if writable?(obj), do: "open_write_modal"}
                phx-value-type={if writable?(obj), do: obj.type}
                phx-value-instance={if writable?(obj), do: obj.instance}
                title={if writable?(obj), do: t(@locale, @locale_version, "Klicken zum Schreiben")}
              >
                {present_value_label(obj)}
              </td>
              <td
                class="bac-text-faint bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, obj, @list_opts))}
              >
                {format_time(obj.updated_at)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr(:column, :string, required: true)
  attr(:label, :string, required: true)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)

  def sort_header(assigns) do
    ~H"""
    <button
      type="button"
      id={"object-sort-#{@column}"}
      phx-click="sort_objects"
      phx-value-column={@column}
      class={[
        "bac-sort-header",
        @sort_by == @column && "bac-sort-header-active"
      ]}
      aria-sort={if @sort_by == @column, do: Atom.to_string(@sort_dir), else: "none"}
    >
      <span>{@label}</span>
      <.icon
        :if={@sort_by == @column && @sort_dir == :asc}
        name="hero-chevron-up"
        class="size-3.5"
      />
      <.icon
        :if={@sort_by == @column && @sort_dir == :desc}
        name="hero-chevron-down"
        class="size-3.5"
      />
      <.icon
        :if={@sort_by != @column}
        name="hero-chevron-up-down"
        class="size-3.5 opacity-35"
      />
    </button>
    """
  end

  @doc false
  def list_objects(objects, search, type_filter, status_filter, sort_by, sort_dir) do
    objects
    |> filtered_objects(search, type_filter, status_filter)
    |> sorted_objects(sort_by, sort_dir)
  end

  @doc false
  def parse_search_query(search), do: SearchQuery.parse(search)

  @doc false
  def filtered_objects(objects, search, type_filter, status_filter \\ []) do
    query = SearchQuery.parse(search)

    Enum.filter(objects, fn obj ->
      type_ok = type_filter == [] or obj.type in type_filter
      status_ok = status_filter == [] or matches_status_filter?(obj, status_filter)
      search_ok = SearchQuery.matches?(query, object_search_haystack(obj))

      type_ok and status_ok and search_ok
    end)
  end

  @doc false
  def sorted_objects(objects, sort_by, sort_dir) when sort_by in @sort_columns do
    Enum.sort_by(objects, &sort_key(&1, sort_by), sort_dir)
  end

  def sorted_objects(objects, _sort_by, _sort_dir), do: objects

  @doc false
  def normalize_sort_column(column) when column in @sort_columns, do: column

  def normalize_sort_column(column) when is_atom(column) do
    normalize_sort_column(Atom.to_string(column))
  end

  def normalize_sort_column(_column), do: nil

  @doc false
  def normalize_sort_dir(dir) when dir in [:asc, :desc], do: dir
  def normalize_sort_dir("asc"), do: :asc
  def normalize_sort_dir("desc"), do: :desc
  def normalize_sort_dir(_dir), do: :asc

  @doc false
  def toggle_sort(nil, _sort_dir, column), do: {column, :asc}

  def toggle_sort(column, :asc, column), do: {column, :desc}
  def toggle_sort(column, :desc, column), do: {column, :asc}
  def toggle_sort(_sort_by, _sort_dir, column), do: {column, :asc}

  @doc false
  def available_types(objects) when is_list(objects) do
    objects
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, objs} ->
      %{
        type: type,
        label: ObjectTypes.short_label(type),
        count: length(objs)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  @doc false
  def type_filter_active?(type_filter), do: type_filter != []

  @doc false
  def type_checked?(type_filter, _available_types, type) do
    type_filter == [] or type in type_filter
  end

  @doc false
  def toggle_type_filter(type_filter, available_types, type) do
    available = Enum.map(available_types, & &1.type)
    effective = if type_filter == [], do: available, else: type_filter

    new =
      if type in effective do
        List.delete(effective, type)
      else
        [type | effective]
      end

    if MapSet.new(new) == MapSet.new(available), do: [], else: Enum.sort(new)
  end

  @doc false
  def filter_type_only(type), do: [type]

  @doc false
  def available_status_flags(objects) when is_list(objects) do
    @status_filter_flags
    |> Enum.map(fn flag ->
      %{
        flag: flag,
        count: Enum.count(objects, &object_has_status_flag?(&1, flag))
      }
    end)
    |> Enum.filter(fn %{count: count} -> count > 0 end)
  end

  @doc false
  def status_filter_active?(status_filter), do: status_filter != []

  @doc false
  def status_checked?(status_filter, _available_statuses, flag) do
    status_filter == [] or flag in status_filter
  end

  @doc false
  def toggle_status_filter(status_filter, available_statuses, flag) do
    available = Enum.map(available_statuses, & &1.flag)
    effective = if status_filter == [], do: available, else: status_filter

    new =
      if flag in effective do
        List.delete(effective, flag)
      else
        [flag | effective]
      end

    if MapSet.new(new) == MapSet.new(available), do: [], else: Enum.sort(new)
  end

  @doc false
  def filter_status_only(flag), do: [flag]

  @doc false
  def normalize_status_flag(flag) when flag in @status_filter_flags, do: flag

  def normalize_status_flag(flag) when is_binary(flag) do
    case flag do
      "in_alarm" -> :in_alarm
      "fault" -> :fault
      "overridden" -> :overridden
      "out_of_service" -> :out_of_service
      "none" -> :none
      _flag -> nil
    end
  end

  def normalize_status_flag(_flag), do: nil

  @doc false
  def encode_status_flags(flags) when is_list(flags) do
    flags
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
    |> Enum.join(",")
  end

  @doc false
  def object_active_status_flags(obj) do
    StatusFlagsIcons.active_flags(Map.get(obj, :status_flags))
  end

  @doc false
  def object_has_status_flag?(obj, :none), do: object_active_status_flags(obj) == []

  def object_has_status_flag?(obj, flag),
    do: flag in object_active_status_flags(obj)

  @doc false
  def matches_status_filter?(obj, status_filter) when is_list(status_filter) do
    Enum.any?(status_filter, &object_has_status_flag?(obj, &1))
  end

  defp sort_key(obj, "object_id"), do: {obj.type, obj.instance}
  defp sort_key(obj, "name"), do: nullable_string_key(obj.name)
  defp sort_key(obj, "description"), do: nullable_string_key(object_description(obj))
  defp sort_key(obj, "type"), do: nullable_string_key(obj.type_label || Atom.to_string(obj.type))
  defp sort_key(obj, "present_value"), do: present_value_key(obj)
  defp sort_key(obj, "updated_at"), do: updated_at_key(obj.updated_at)

  defp nullable_string_key(nil), do: {1, NaturalSort.key("")}
  defp nullable_string_key(value), do: {0, NaturalSort.key(value)}

  defp present_value_key(obj) do
    case Map.get(obj, :present_value) do
      value when is_float(value) -> {0, value}
      value when is_integer(value) -> {0, value * 1.0}
      value when is_boolean(value) -> {1, value}
      nil -> {3, ""}
      value -> {2, String.downcase(to_string(value))}
    end
  end

  defp updated_at_key(%DateTime{} = dt), do: {0, DateTime.to_unix(dt, :microsecond)}
  defp updated_at_key(_updated_at_key), do: {1, 0}

  defp object_path(device_id, obj, list_opts) do
    DeviceUrl.object_path(device_id, obj.type, obj.instance,
      tab: "objects",
      search: list_opts.search,
      types: list_opts.type_filter,
      status: list_opts.status_filter,
      sort: list_opts.sort_by,
      dir: list_opts.sort_dir
    )
  end

  defp object_search_haystack(obj) do
    String.downcase(
      "#{Map.get(obj, :type)} #{Map.get(obj, :type_label)} #{Map.get(obj, :instance)} #{Map.get(obj, :name)} #{object_description(obj)}"
    )
  end

  defp object_description(obj) when is_map(obj), do: Map.get(obj, :description)
  defp object_description(_obj), do: nil

  defp writable?(obj) when is_map(obj), do: Map.get(obj, :writable, false)
  defp writable?(_obj), do: false

  defp commandable?(obj) when is_map(obj), do: Map.get(obj, :commandable, false)

  defp present_value_label(obj) when is_map(obj) do
    formatted = Map.get(obj, :present_value_formatted, "-")

    if commandable?(obj) && Map.get(obj, :active_priority) do
      "#{formatted} (#{obj.active_priority})"
    else
      formatted
    end
  end

  defp present_value_label(_obj), do: "-"

  defp selected?(keys, obj),
    do: MapSet.member?(keys, {obj.type, obj.instance})

  defp all_selected?(keys, objects) when is_list(objects) do
    objects != [] and
      Enum.all?(objects, &selected?(keys, &1))
  end

  defp live?(keys, obj), do: MapSet.member?(keys, {obj.type, obj.instance, :present_value})

  defp flash_class(cells, obj) do
    if MapSet.member?(cells, {obj.type, obj.instance}),
      do: "bac-row-flash",
      else: ""
  end

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt),
    do: BacView.Timezone.format(dt, "%H:%M:%S")
end
