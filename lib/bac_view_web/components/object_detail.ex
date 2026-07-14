defmodule BacViewWeb.ObjectDetail do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.PropertyWriter

  alias BacView.BACnet.Protocol.TrendLogReader

  alias BacView.BACnet.HierarchySplit
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.FileTransferPanel
  alias BacViewWeb.ObjectTypeIcon
  alias BacViewWeb.PropertyTable
  alias BacViewWeb.PropertyValue
  alias BacViewWeb.SortHeader
  alias BacViewWeb.StatusFlagsIcons

  attr(:device, :map, required: true)
  attr(:return_tab, :string, default: "hierarchy")
  attr(:return_alarm_view, :string, default: "active_alarms")
  attr(:return_cov_view, :string, default: "subscriptions")
  attr(:return_hierarchy_view, :string, default: "explorer")
  attr(:return_hierarchy_path, :list, default: [])
  attr(:return_hierarchy_split, :any, default: nil)
  attr(:objects_search, :string, default: "")
  attr(:objects_type_filter, :list, default: [])
  attr(:objects_status_filter, :list, default: [])
  attr(:objects_sort_by, :string, default: nil)
  attr(:objects_sort_dir, :atom, default: :asc)
  attr(:object, :map, default: nil)
  attr(:properties, :list, default: [])
  attr(:unknown_properties, :list, default: [])
  attr(:properties_sort_by, :string, default: nil)
  attr(:properties_sort_dir, :atom, default: :asc)
  attr(:unknown_properties_sort_by, :string, default: nil)
  attr(:unknown_properties_sort_dir, :atom, default: :asc)
  attr(:unknown_property_hex_keys, :any, default: MapSet.new())
  attr(:loading, :boolean, default: false)
  attr(:properties_loading, :boolean, default: false)
  attr(:subscribed_keys, :any, default: MapSet.new())
  attr(:write_priority, :integer, default: 8)
  attr(:writing_property, :any, default: nil)
  attr(:file_metadata, :map, default: nil)
  attr(:file_content, :map, default: nil)
  attr(:file_transfer_busy, :boolean, default: false)
  attr(:uploads, :map, default: %{})
  attr(:object_nav_targets, :list, default: [])
  attr(:object_nav_menu_open, :boolean, default: false)

  def object_detail(assigns) do
    assigns =
      assigns
      |> assign(
        :sorted_properties,
        PropertyTable.sorted_properties(
          assigns.properties,
          assigns.properties_sort_by,
          assigns.properties_sort_dir
        )
      )
      |> assign(
        :sorted_unknown_properties,
        PropertyTable.sorted_unknown_properties(
          assigns.unknown_properties,
          assigns.unknown_properties_sort_by,
          assigns.unknown_properties_sort_dir
        )
      )

    ~H"""
    <div class="flex flex-col flex-1 min-h-0">
      <header class="bac-panel-header items-start px-5 border-b border-[var(--bac-border)]">
        <.link
          navigate={device_return_path(@device.id, assigns)}
          class="bac-btn bac-btn-ghost bac-btn-icon mt-0.5"
          title={return_tab_title(@return_tab, @locale, @locale_version)}
        >
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <div class="flex-1 min-w-0 flex flex-col items-start">
          <p class="text-xs bac-text-faint uppercase tracking-wide">
            {t(@locale, @locale_version, "Objektdetails")}
          </p>
          <div class="flex flex-wrap items-center justify-start gap-6 mt-0.5 w-fit max-w-full">
            <div class="min-w-0 shrink-0">
              <h1 class="font-semibold text-base truncate">
                {@object && @object.name || t(@locale, @locale_version, "Unbenanntes Objekt")}
              </h1>
              <p :if={@object} class="bac-mono text-xs bac-text-faint mt-0.5">
                {@object.type}:{@object.instance}
              </p>
            </div>
            <div
              :if={
                @object && show_status_flags_in_header?(@object, @properties, @properties_loading)
              }
              class="shrink-0 pl-4"
            >
              <StatusFlagsIcons.status_flags_icons
                flags={@object.status_flags}
                mode={:stats}
              />
            </div>
          </div>
        </div>
        <div :if={@object} class="flex items-center gap-2 shrink-0 pt-0.5">
          <span :if={live?(@subscribed_keys, @object)} class="bac-badge bac-badge-success">
            <.icon name="hero-signal" class="size-3" />
            {t(@locale, @locale_version, "Live")}
          </span>
          <button
            :if={header_trend_chart?(@object)}
            type="button"
            id="trend-chart-open-header"
            phx-click="open_trend_chart_modal"
            class="bac-btn bac-btn-ghost bac-btn-sm"
          >
            <.icon name="hero-chart-bar" class="size-4" />
            {t(@locale, @locale_version, "Diagramm")}
          </button>
          <.object_nav_controls
            :if={@object_nav_targets != []}
            object={@object}
            targets={@object_nav_targets}
            menu_open={@object_nav_menu_open}
            locale={@locale}
            locale_version={@locale_version}
          />
          <button
            :if={!subscribed?(@subscribed_keys, @object, :present_value)}
            type="button"
            phx-click="subscribe_cov"
            phx-value-type={@object.type}
            phx-value-instance={@object.instance}
            phx-value-property="present_value"
            disabled={@properties_loading}
            class="bac-btn bac-btn-primary bac-btn-sm"
          >
            <.icon name="hero-signal" class="size-4" />
            {t(@locale, @locale_version, "COV abonnieren")}
          </button>
          <button
            :if={subscribed?(@subscribed_keys, @object, :present_value)}
            type="button"
            phx-click="unsubscribe_cov"
            phx-value-type={@object.type}
            phx-value-instance={@object.instance}
            phx-value-property="present_value"
            disabled={@properties_loading}
            class="bac-btn bac-btn-ghost bac-btn-sm"
          >
            {t(@locale, @locale_version, "COV kündigen")}
          </button>
          <button
            type="button"
            id="refresh-properties-btn"
            phx-click="refresh_properties"
            disabled={@properties_loading}
            class={["bac-btn bac-btn-ghost bac-btn-sm", @properties_loading && "opacity-80"]}
            title={t(@locale, @locale_version, "Aktualisieren")}
            aria-busy={to_string(@properties_loading)}
          >
            <.icon
              name="hero-arrow-path"
              class={
                if(@properties_loading,
                  do: "size-4 animate-spin text-[var(--bac-accent)]",
                  else: "size-4"
                )
              }
            />
          </button>
        </div>
      </header>

      <div
        :if={@object && @properties_loading}
        id="object-refresh-banner"
        role="status"
        aria-live="polite"
        class="mx-5 mt-3 rounded-lg border border-[var(--bac-accent)]/25 bg-[var(--bac-accent)]/8 px-4 py-3"
      >
        <div class="flex items-center gap-3 min-w-0">
          <.icon
            name="hero-arrow-path"
            class="size-4 shrink-0 animate-spin text-[var(--bac-accent)]"
          />
          <p class="text-sm font-medium text-[var(--bac-text)]">
            {t(@locale, @locale_version, "Eigenschaften werden gelesen…")}
          </p>
        </div>
        <p class="text-xs bac-text-muted mt-1.5 ml-7">
          {t(@locale, @locale_version, "Warte auf BACnet-Antwort…")}
        </p>
      </div>

      <div class="flex-1 min-w-0 overflow-auto p-5 space-y-5">
        <div :if={@loading} class="bac-loading py-16">
          <.icon name="hero-arrow-path" class="size-5 animate-spin" />
          {t(@locale, @locale_version, "Objekt wird geladen…")}
        </div>

        <div :if={!@loading && is_nil(@object)} class="bac-hero py-16">
          <div class="bac-hero-icon">
            <.icon name="hero-cube" class="size-7" />
          </div>
          <p class="bac-hero-text">{t(@locale, @locale_version, "Objekt nicht gefunden.")}</p>
          <.link
            navigate={device_return_path(@device.id, assigns)}
            class="bac-btn bac-btn-primary bac-btn-sm"
          >
            {return_tab_button_label(@return_tab, @locale, @locale_version)}
          </.link>
        </div>

        <section
          :if={!@loading && @object}
          class={["bac-object-hero", @properties_loading && "bac-object-hero-reading"]}
        >
          <div class="bac-object-hero-icon">
            <.icon name={ObjectTypeIcon.name(@object.type)} class="size-8" />
          </div>
          <div class="flex-1 min-w-0 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div class="bac-stat">
              <p class="bac-stat-label">{t(@locale, @locale_version, "Typ")}</p>
              <p class="bac-stat-value text-sm">{ObjectTypes.label(@object.type)}</p>
            </div>
            <div class="bac-stat">
              <p class="bac-stat-label">{t(@locale, @locale_version, "Present Value")}</p>
              <p class="bac-stat-value bac-mono text-lg">{@object.present_value_formatted}</p>
            </div>
            <div :if={@object.units} class="bac-stat">
              <p class="bac-stat-label">{t(@locale, @locale_version, "Einheit")}</p>
              <p class="bac-stat-value bac-mono text-sm">{EngineeringUnits.label(@object.units)}</p>
            </div>
            <div class="bac-stat">
              <p class="bac-stat-label">{t(@locale, @locale_version, "Aktualisiert")}</p>
              <p class="bac-stat-value text-sm">{format_time(@object.updated_at)}</p>
            </div>
          </div>
        </section>

        <FileTransferPanel.panel
          :if={!@loading && @object && @object.type == :file && @file_metadata}
          metadata={@file_metadata}
          content={@file_content}
          busy={@file_transfer_busy}
          uploads={@uploads}
          locale={@locale}
          locale_version={@locale_version}
        />

        <section
          :if={!@loading && @object}
          id="object-properties-panel"
          class="bac-panel w-full min-w-0"
          aria-busy={to_string(@properties_loading)}
        >
          <div :if={@properties_loading} class="bac-reading-bar" aria-hidden="true"></div>
          <div class="bac-panel-header flex-wrap gap-3">
            <div class="min-w-0">
              <p class="bac-section-title">{t(@locale, @locale_version, "Eigenschaften")}</p>
              <p
                :if={!@properties_loading && @properties != []}
                class="text-xs bac-text-faint"
              >
                {t(@locale, @locale_version, "%{count} Eigenschaften", count: length(@properties))}
              </p>
              <p :if={@properties_loading && @properties == []} class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Eigenschaften werden gelesen…")}
              </p>
            </div>
            <div :if={commandable?(@object)} class="flex items-center gap-2 ml-auto">
              <label for="write-priority" class="text-xs bac-text-faint whitespace-nowrap">
                {t(@locale, @locale_version, "Schreib-Priorität")}
              </label>
              <select
                id="write-priority"
                name="priority"
                phx-change="set_write_priority"
                class="bac-input bac-input-sm w-20"
              >
                <option
                  :for={p <- 1..16}
                  value={p}
                  selected={p == @write_priority}
                >
                  {p}
                </option>
              </select>
            </div>
          </div>

          <div :if={@properties_loading && @properties == []} class="bac-loading py-12">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" />
            {t(@locale, @locale_version, "Eigenschaften werden gelesen…")}
          </div>

          <div :if={!@properties_loading && @properties == []} class="bac-hero py-12">
            <p class="text-sm bac-text-muted">{t(@locale, @locale_version, "Keine Eigenschaften verfügbar.")}</p>
          </div>

          <div
            :if={@properties != []}
            class={[
              "bac-table-wrap border-0 rounded-none",
              @properties_loading && "bac-table-reading"
            ]}
          >
            <table class="bac-table" id="object-detail-properties-table">
              <colgroup>
                <col class="w-[22%]" />
                <col class="w-[40%]" />
                <col class="w-[18%]" />
                <col class="w-[20%]" />
              </colgroup>
              <thead>
                <tr>
                  <th>
                    <SortHeader.sort_header
                      event="sort_properties"
                      id_prefix="property-sort"
                      column="name"
                      label={t(@locale, @locale_version, "Name")}
                      sort_by={@properties_sort_by}
                      sort_dir={@properties_sort_dir}
                    />
                  </th>
                  <th>
                    <SortHeader.sort_header
                      event="sort_properties"
                      id_prefix="property-sort"
                      column="value"
                      label={t(@locale, @locale_version, "Wert")}
                      sort_by={@properties_sort_by}
                      sort_dir={@properties_sort_dir}
                    />
                  </th>
                  <th>
                    <SortHeader.sort_header
                      event="sort_properties"
                      id_prefix="property-sort"
                      column="type"
                      label={t(@locale, @locale_version, "Typ")}
                      sort_by={@properties_sort_by}
                      sort_dir={@properties_sort_dir}
                    />
                  </th>
                  <th>
                    <SortHeader.sort_header
                      event="sort_properties"
                      id_prefix="property-sort"
                      column="actions"
                      label={t(@locale, @locale_version, "Aktionen")}
                      sort_by={@properties_sort_by}
                      sort_dir={@properties_sort_dir}
                    />
                  </th>
                </tr>
              </thead>
              <tbody id="object-properties">
                <tr :for={prop <- @sorted_properties} id={"prop-#{prop.property}"}>
                  <td class="bac-mono align-top">{prop.property_name}</td>
                  <td class="align-top min-w-0">
                    <div :if={!property_writable_in_ui?(prop)}>
                      <PropertyValue.property_value
                        display={prop.value_display}
                        writable={false}
                        property={prop.property}
                        locale={@locale}
                        locale_version={@locale_version}
                      />
                    </div>
                    <.form
                      :if={property_writable_in_ui?(prop) && struct_writable?(prop)}
                      for={%{}}
                      as={:write}
                      id={"write-form-#{prop.property}"}
                      phx-submit="write_property"
                      class="bac-property-write space-y-2"
                    >
                      <input type="hidden" name="property" value={prop.property} />
                      <input
                        :if={commandable?(@object)}
                        type="hidden"
                        name="priority"
                        value={@write_priority}
                      />
                      <PropertyValue.property_value
                        display={prop.value_display}
                        writable={true}
                        property={prop.property}
                        writing={@writing_property == prop.property}
                        locale={@locale}
                        locale_version={@locale_version}
                      />
                      <.write_actions
                        object={@object}
                        prop={prop}
                        writing_property={@writing_property}
                        write_priority={@write_priority}
                        locale={@locale}
                        locale_version={@locale_version}
                      />
                    </.form>
                    <div :if={property_writable_in_ui?(prop) && complex_writable?(prop)} class="space-y-2">
                      <PropertyValue.property_value
                        display={prop.value_display}
                        writable={false}
                        property={prop.property}
                        locale={@locale}
                        locale_version={@locale_version}
                      />
                      <button
                        type="button"
                        phx-click="open_write_property_modal"
                        phx-value-property={property_param(prop.property)}
                        class="bac-btn bac-btn-ghost bac-btn-xs"
                      >
                        <.icon name="hero-pencil-square" class="size-3.5" />
                        {t(@locale, @locale_version, "Bearbeiten")}
                      </button>
                    </div>
                    <.form
                      :if={property_writable_in_ui?(prop) && simple_writable?(prop)}
                      for={%{}}
                      as={:write}
                      id={"write-form-#{prop.property}"}
                      phx-submit="write_property"
                      class="bac-property-write space-y-2"
                    >
                      <input type="hidden" name="property" value={prop.property} />
                      <input
                        :if={commandable?(@object)}
                        type="hidden"
                        name="priority"
                        value={@write_priority}
                      />
                      <label :if={boolean_property?(prop)} class="flex items-center gap-2">
                        <input type="hidden" name="value" value="false" />
                        <input
                          type="checkbox"
                          name="value"
                          value="true"
                          checked={prop.value == true}
                          class="bac-checkbox"
                        />
                        <span class="text-sm">{t(@locale, @locale_version, "Aktiv")}</span>
                      </label>
                      <select
                        :if={enumeration_property?(prop)}
                        name="value"
                        class="bac-input bac-input-sm w-full"
                      >
                        <option
                          :if={is_nil(prop.value)}
                          value=""
                          selected
                        >
                          {t(@locale, @locale_version, "Bitte wählen…")}
                        </option>
                        <option
                          :for={opt <- prop.enum_options}
                          value={opt.value}
                          selected={enum_option_selected?(prop.value, opt.value)}
                        >
                          {opt.label}
                        </option>
                      </select>
                      <input
                        :if={!boolean_property?(prop) && !enumeration_property?(prop)}
                        type="text"
                        name="value"
                        value={input_value(prop, @object)}
                        placeholder={write_placeholder(prop)}
                        class="bac-input bac-input-sm bac-mono w-full"
                      />
                      <.write_actions
                        object={@object}
                        prop={prop}
                        writing_property={@writing_property}
                        write_priority={@write_priority}
                        locale={@locale}
                        locale_version={@locale_version}
                      />
                    </.form>
                  </td>
                  <td class="bac-text-faint align-top">{prop.type}</td>
                  <td class="align-top">
                    <button
                      :if={
                        log_buffer_chart?(prop, @object) &&
                          TrendLogReader.trend_log_type?(@object.type)
                      }
                      type="button"
                      id="trend-chart-open"
                      phx-click="open_trend_chart_modal"
                      class="bac-btn bac-btn-ghost bac-btn-xs"
                    >
                      <.icon name="hero-chart-bar" class="size-3.5" />
                      {t(@locale, @locale_version, "Diagramm")}
                    </button>
                    <button
                      :if={
                        cov_subscribable?(prop.property) &&
                          !subscribed?(@subscribed_keys, @object, prop.property)
                      }
                      type="button"
                      phx-click="subscribe_cov"
                      phx-value-type={@object.type}
                      phx-value-instance={@object.instance}
                      phx-value-property={prop.property}
                      class="bac-btn bac-btn-ghost bac-btn-xs"
                    >
                      COV
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section
          :if={!@loading && @object && @unknown_properties != []}
          id="object-unknown-properties-panel"
          class="bac-panel w-full min-w-0"
          aria-busy={to_string(@properties_loading)}
        >
          <div class="bac-panel-header">
            <div class="min-w-0">
              <p class="bac-section-title">
                {t(@locale, @locale_version, "Unbekannte Eigenschaften")}
              </p>
              <p class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "%{count} unbekannte Eigenschaften",
                  count: length(@unknown_properties)
                )}
              </p>
            </div>
          </div>

          <div
            class={[
              "bac-table-wrap border-0 rounded-none",
              @properties_loading && "bac-table-reading"
            ]}
          >
            <table class="bac-table" id="object-detail-unknown-properties-table">
              <colgroup>
                <col class="w-[28%]" />
                <col class="w-[52%]" />
                <col class="w-[20%]" />
              </colgroup>
              <thead>
                <tr>
                  <th>
                    <SortHeader.sort_header
                      event="sort_unknown_properties"
                      id_prefix="unknown-property-sort"
                      column="name"
                      label={t(@locale, @locale_version, "Name")}
                      sort_by={@unknown_properties_sort_by}
                      sort_dir={@unknown_properties_sort_dir}
                    />
                  </th>
                  <th>
                    <SortHeader.sort_header
                      event="sort_unknown_properties"
                      id_prefix="unknown-property-sort"
                      column="value"
                      label={t(@locale, @locale_version, "Wert")}
                      sort_by={@unknown_properties_sort_by}
                      sort_dir={@unknown_properties_sort_dir}
                    />
                  </th>
                  <th>
                    <SortHeader.sort_header
                      event="sort_unknown_properties"
                      id_prefix="unknown-property-sort"
                      column="type"
                      label={t(@locale, @locale_version, "Typ")}
                      sort_by={@unknown_properties_sort_by}
                      sort_dir={@unknown_properties_sort_dir}
                    />
                  </th>
                </tr>
              </thead>
              <tbody id="object-unknown-properties">
                <tr :for={prop <- @sorted_unknown_properties} id={"unknown-prop-#{prop.property}"}>
                  <td class="bac-mono align-top">{prop.property_name}</td>
                  <td class="align-top min-w-0">
                    <.unknown_property_value
                      prop={prop}
                      hex_keys={@unknown_property_hex_keys}
                      locale={@locale}
                      locale_version={@locale_version}
                    />
                  </td>
                  <td class="bac-text-faint align-top">{prop.type}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr(:prop, :map, required: true)
  attr(:hex_keys, :any, required: true)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp unknown_property_value(assigns) do
    assigns =
      assign(assigns, :hex_mode?, MapSet.member?(assigns.hex_keys, assigns.prop.property))

    ~H"""
    <div :if={@prop[:string_value?]} class="space-y-2">
      <span class="bac-mono text-sm text-[var(--bac-text)] break-all">
        {unknown_property_display_text(@prop, @hex_mode?)}
      </span>
      <button
        type="button"
        id={"unknown-prop-hex-toggle-#{@prop.property}"}
        phx-click="toggle_unknown_property_hex"
        phx-value-property={property_param(@prop.property)}
        class="bac-btn bac-btn-ghost bac-btn-xs"
      >
        {unknown_property_hex_toggle_label(@hex_mode?, @locale, @locale_version)}
      </button>
    </div>
    <PropertyValue.property_value
      :if={!@prop[:string_value?]}
      display={@prop.value_display}
      writable={false}
      property={@prop.property}
      locale={@locale}
      locale_version={@locale_version}
    />
    """
  end

  defp unknown_property_display_text(%{raw_binary: binary, value_formatted: formatted}, false)
       when is_binary(binary),
       do: formatted

  defp unknown_property_display_text(%{raw_binary: binary}, true) when is_binary(binary),
    do: PropertyFormatter.format_binary_hex(binary)

  defp unknown_property_hex_toggle_label(true, locale, locale_version),
    do: t(locale, locale_version, "Als Text")

  defp unknown_property_hex_toggle_label(false, locale, locale_version),
    do: t(locale, locale_version, "Als Hex")

  defp subscribed?(keys, object, property) when is_map(object) do
    MapSet.member?(keys, {object.type, object.instance, normalize_property(property)})
  end

  defp subscribed?(_keys, _object2, _object), do: false

  defp live?(keys, obj), do: MapSet.member?(keys, {obj.type, obj.instance, :present_value})

  defp show_status_flags_in_header?(_object, properties, _properties_loading)
       when is_list(properties) do
    Enum.any?(properties, &(&1.property == :status_flags))
  end

  defp show_status_flags_in_header?(_object, _properties, _properties_loading), do: false

  defp property_writable_in_ui?(%{property: :log_buffer}), do: false
  defp property_writable_in_ui?(%{writable: writable}), do: writable

  defp log_buffer_chart?(%{property: :log_buffer}, _object), do: true
  defp log_buffer_chart?(_object, _log_buffer_chart2), do: false

  defp header_trend_chart?(%{type: type}), do: TrendLogReader.trend_log_type?(type)
  defp header_trend_chart?(_object), do: false

  defp cov_subscribable?(:log_buffer), do: false

  defp cov_subscribable?(property) do
    property in [:present_value, :status_flags, :event_state] or
      (is_atom(property) and property not in [:object_identifier, :object_name, :object_type])
  end

  defp normalize_property("present_value"), do: :present_value
  defp normalize_property(prop) when is_atom(prop), do: prop
  defp normalize_property(prop) when is_binary(prop), do: String.to_existing_atom(prop)

  defp commandable?(object), do: PropertyWriter.commandable_for_ui?(object)

  defp resettable?(object, %{property: :present_value}),
    do: PropertyWriter.commandable_for_ui?(object)

  defp resettable?(_object, _resettable2), do: false

  defp struct_writable?(%{value_display: %{kind: :struct, fields: fields}}) when fields != [] do
    Enum.all?(fields, &(&1.kind == :boolean))
  end

  defp struct_writable?(_struct_writable), do: false

  defp complex_writable?(prop) do
    not struct_writable?(prop) and not simple_writable?(prop)
  end

  defp simple_writable?(prop) do
    boolean_property?(prop) or enumeration_property?(prop) or
      (scalar_property_value?(prop) and not complex_property_display?(prop))
  end

  defp complex_property_display?(%{value_display: %{kind: kind}} = prop)
       when kind in [:struct, :array, :priority_array, :object_identifier] do
    not PropertyEnumeration.dropdown?(prop)
  end

  defp complex_property_display?(%{value: %_prop{}} = prop),
    do: not PropertyEnumeration.dropdown?(prop)

  defp complex_property_display?(_prop), do: false

  defp scalar_property_value?(prop) do
    case Map.get(prop, :value) do
      value when is_number(value) or is_binary(value) or is_boolean(value) -> true
      value when is_atom(value) and value not in [:unspecified, nil] -> true
      _prop -> false
    end
  end

  defp boolean_property?(%{bac_type: :boolean}), do: true
  defp boolean_property?(%{type: "BOOLEAN"}), do: true
  defp boolean_property?(%{value: value}) when is_boolean(value), do: true
  defp boolean_property?(_value), do: false

  defp enumeration_property?(prop), do: PropertyEnumeration.dropdown?(prop)

  defp enum_option_selected?(value, option_value)
       when is_integer(value) and is_integer(option_value),
       do: value == option_value

  defp enum_option_selected?(value, option_value)
       when is_float(value) and is_integer(option_value),
       do: trunc(value) == option_value

  defp enum_option_selected?(value, option_value)
       when is_integer(value) and is_float(option_value),
       do: value == trunc(option_value)

  defp enum_option_selected?(value, option_value) when is_float(value) and is_float(option_value),
    do: trunc(value) == trunc(option_value)

  defp enum_option_selected?(value, option_value), do: value == option_value

  attr(:object, :map, required: true)
  attr(:prop, :map, required: true)
  attr(:writing_property, :any, default: nil)
  attr(:write_priority, :integer, default: 8)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp write_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5">
      <button
        type="submit"
        disabled={@writing_property == @prop.property}
        class="bac-btn bac-btn-primary bac-btn-xs"
      >
        <.icon
          :if={@writing_property == @prop.property}
          name="hero-arrow-path"
          class="size-3 animate-spin"
        />
        {t(@locale, @locale_version, "Schreiben")}
      </button>
      <button
        :if={resettable?(@object, @prop)}
        type="button"
        phx-click="reset_property"
        phx-value-property={@prop.property}
        phx-value-priority={@write_priority}
        disabled={@writing_property == @prop.property}
        class="bac-btn bac-btn-ghost bac-btn-xs"
        title={t(@locale, @locale_version, "Null schreiben (Priorität zurücksetzen)")}
      >
        {t(@locale, @locale_version, "Null")}
      </button>
    </div>
    """
  end

  defp input_value(prop, object) do
    PropertyFormatter.format_edit_value(Map.get(prop, :value), object, prop)
  end

  defp write_placeholder(%{property: :present_value, type: "REAL"}),
    do: dgettext(BacViewWeb.Gettext, "default", "z. B. 21.5")

  defp write_placeholder(%{type: "BOOLEAN"}),
    do: dgettext(BacViewWeb.Gettext, "default", "true oder false")

  defp write_placeholder(_Gettext), do: dgettext(BacViewWeb.Gettext, "default", "Neuer Wert")

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt),
    do: BacView.Timezone.format(dt, "%d.%m.%Y %H:%M:%S")

  defp property_param(property) when is_atom(property), do: Atom.to_string(property)
  defp property_param(property) when is_integer(property), do: Integer.to_string(property)
  defp property_param(property), do: to_string(property)

  defp device_return_path(device_id, assigns) do
    DeviceUrl.device_path(device_id,
      tab: assigns.return_tab,
      search: assigns.objects_search,
      types: assigns.objects_type_filter,
      status: assigns.objects_status_filter,
      sort: assigns.objects_sort_by,
      dir: assigns.objects_sort_dir,
      alarm_view: assigns.return_alarm_view,
      cov_view: assigns.return_cov_view,
      hierarchy_view: assigns.return_hierarchy_view,
      hierarchy_path: assigns.return_hierarchy_path,
      h_split: HierarchySplit.encode(assigns.return_hierarchy_split)
    )
  end

  defp return_tab_title("hierarchy", locale, locale_version),
    do: t(locale, locale_version, "Zurück zur Hierarchie")

  defp return_tab_title("objects", locale, locale_version),
    do: t(locale, locale_version, "Zurück zur Objektliste")

  defp return_tab_title(_tab, locale, locale_version),
    do: t(locale, locale_version, "Zurück zur Geräteansicht")

  defp return_tab_button_label("hierarchy", locale, locale_version),
    do: t(locale, locale_version, "Zur Hierarchie")

  defp return_tab_button_label("objects", locale, locale_version),
    do: t(locale, locale_version, "Zur Objektliste")

  defp return_tab_button_label(_tab, locale, locale_version),
    do: t(locale, locale_version, "Zur Geräteansicht")

  attr(:object, :map, required: true)
  attr(:targets, :list, required: true)
  attr(:menu_open, :boolean, default: false)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp object_nav_controls(assigns) do
    assigns =
      assign(
        assign(assigns, :nav_kind, nav_kind(assigns.object)),
        :single_target,
        List.first(assigns.targets)
      )

    ~H"""
    <.link
      :if={length(@targets) == 1}
      id="object-nav-jump"
      navigate={@single_target.href}
      class="bac-btn bac-btn-ghost bac-btn-sm"
      title={@single_target.label}
    >
      <.icon name={nav_icon(@nav_kind)} class="size-4" />
      {nav_button_label(@nav_kind, @locale, @locale_version)}
    </.link>
    <div :if={length(@targets) > 1} class="relative">
      <button
        type="button"
        id="object-nav-menu-toggle"
        phx-click="toggle_object_nav_menu"
        class="bac-btn bac-btn-ghost bac-btn-sm"
        aria-haspopup="menu"
        aria-expanded={to_string(@menu_open)}
        aria-controls={if(@menu_open, do: "object-nav-menu")}
      >
        <.icon name={nav_icon(@nav_kind)} class="size-4" />
        {nav_menu_button_label(@nav_kind, @locale, @locale_version)}
        <.icon name="hero-chevron-down" class="size-3.5 opacity-70" />
      </button>
      <div
        :if={@menu_open}
        id="object-nav-menu"
        phx-hook="FilterMenu"
        data-trigger-id="object-nav-menu-toggle"
        data-close-event="close_object_nav_menu"
        class="bac-filter-menu"
      >
        <div class="bac-filter-menu-header">
          <p class="text-xs font-semibold text-[var(--bac-text)]">
            {nav_menu_title(@nav_kind, @locale, @locale_version)}
          </p>
        </div>
        <ul class="bac-filter-menu-list">
          <li :for={target <- @targets} class="bac-filter-menu-item">
            <.link
              navigate={target.href}
              class="flex items-center gap-2 w-full text-left text-sm min-w-0"
            >
              <.icon name={ObjectTypeIcon.name(target.type)} class="size-4 shrink-0 opacity-80" />
              <span class="truncate">{target.label}</span>
            </.link>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp nav_kind(%{type: type}) when type in [:trend_log, :trend_log_multiple],
    do: :referenced_object

  defp nav_kind(_object), do: :trend_log

  defp nav_icon(:trend_log), do: "hero-presentation-chart-line"
  defp nav_icon(:referenced_object), do: "hero-cube"

  defp nav_button_label(:trend_log, locale, locale_version),
    do: t(locale, locale_version, "Zum Trendprotokoll")

  defp nav_button_label(:referenced_object, locale, locale_version),
    do: t(locale, locale_version, "Zum Objekt")

  defp nav_menu_button_label(:trend_log, locale, locale_version),
    do: t(locale, locale_version, "Trendprotokolle")

  defp nav_menu_button_label(:referenced_object, locale, locale_version),
    do: t(locale, locale_version, "Referenzierte Objekte")

  defp nav_menu_title(:trend_log, locale, locale_version),
    do: t(locale, locale_version, "Trendprotokolle")

  defp nav_menu_title(:referenced_object, locale, locale_version),
    do: t(locale, locale_version, "Referenzierte Objekte")
end
