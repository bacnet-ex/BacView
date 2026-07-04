defmodule BacViewWeb.ObjectDetail do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.PropertyWriter

  alias BacView.BACnet.Protocol.TrendLogReader

  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.FileTransferPanel
  alias BacViewWeb.ObjectTypeIcon
  alias BacViewWeb.PropertyTable
  alias BacViewWeb.PropertyValue
  alias BacViewWeb.SortHeader
  alias BacViewWeb.StatusFlagsIcons

  attr(:device, :map, required: true)
  attr(:return_tab, :string, default: "hierarchy")
  attr(:return_alarm_view, :string, default: "event_information")
  attr(:return_cov_view, :string, default: "subscriptions")
  attr(:return_hierarchy_view, :string, default: "explorer")
  attr(:return_hierarchy_path, :list, default: [])
  attr(:objects_search, :string, default: "")
  attr(:objects_type_filter, :list, default: [])
  attr(:objects_status_filter, :list, default: [])
  attr(:objects_sort_by, :string, default: nil)
  attr(:objects_sort_dir, :atom, default: :asc)
  attr(:object, :map, default: nil)
  attr(:properties, :list, default: [])
  attr(:properties_sort_by, :string, default: nil)
  attr(:properties_sort_dir, :atom, default: :asc)
  attr(:loading, :boolean, default: false)
  attr(:properties_loading, :boolean, default: false)
  attr(:properties_reading_visible, :boolean, default: false)
  attr(:subscribed_keys, :any, default: MapSet.new())
  attr(:write_priority, :integer, default: 8)
  attr(:writing_property, :any, default: nil)
  attr(:file_metadata, :map, default: nil)
  attr(:file_content, :map, default: nil)
  attr(:file_transfer_busy, :boolean, default: false)
  attr(:uploads, :map, default: %{})

  def object_detail(assigns) do
    assigns =
      assign(
        assigns,
        :sorted_properties,
        PropertyTable.sorted_properties(
          assigns.properties,
          assigns.properties_sort_by,
          assigns.properties_sort_dir
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
          <span
            :if={@properties_reading_visible}
            id="object-reading-status"
            class="bac-badge bac-badge-sm bac-badge-accent inline-flex items-center gap-1.5 max-w-[14rem]"
            role="status"
          >
            <.icon name="hero-arrow-path" class="size-3.5 animate-spin shrink-0" />
            <span class="truncate">
              {t(@locale, @locale_version, "Eigenschaften werden gelesen…")}
            </span>
          </span>
          <span :if={live?(@subscribed_keys, @object)} class="bac-badge bac-badge-success">
            <.icon name="hero-signal" class="size-3" />
            {t(@locale, @locale_version, "Live")}
          </span>
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
            class="bac-btn bac-btn-ghost bac-btn-sm"
            title={t(@locale, @locale_version, "Aktualisieren")}
          >
            <.icon
              name="hero-arrow-path"
              class={if(@properties_loading, do: "size-4 animate-spin", else: "size-4")}
            />
          </button>
        </div>
      </header>

      <div class="flex-1 overflow-auto p-5 space-y-5">
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
          class={["bac-object-hero", @properties_reading_visible && "bac-object-hero-reading"]}
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
          class="bac-panel"
          aria-busy={to_string(@properties_loading)}
        >
          <div :if={@properties_reading_visible} class="bac-reading-bar" aria-hidden="true"></div>
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
              @properties_reading_visible && "bac-table-reading"
            ]}
          >
            <table class="bac-table">
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
                  <td class="align-top min-w-0 max-w-md">
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
                          selected={opt.value == prop.value}
                        >
                          {opt.label}
                        </option>
                      </select>
                      <input
                        :if={!boolean_property?(prop) && !enumeration_property?(prop)}
                        type="text"
                        name="value"
                        value={input_value(prop)}
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
      </div>
    </div>
    """
  end

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
    not enum_dropdown?(prop)
  end

  defp complex_property_display?(%{value: %_prop{}} = prop),
    do: not enum_dropdown?(prop)

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

  defp enumeration_property?(prop), do: enum_dropdown?(prop)

  defp enum_dropdown?(prop) when is_map(prop) do
    case Map.get(prop, :enum_options) do
      options when is_list(options) and options != [] -> true
      _options -> false
    end
  end

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

  defp input_value(%{value: nil}), do: ""
  defp input_value(%{value: v}) when is_float(v), do: PropertyFormatter.format_float(v)
  defp input_value(%{value: true}), do: "true"
  defp input_value(%{value: false}), do: "false"
  defp input_value(%{value: v}) when is_atom(v), do: Atom.to_string(v)
  defp input_value(%{value: v}) when is_integer(v), do: Integer.to_string(v)
  defp input_value(%{value: v}) when is_binary(v), do: v
  defp input_value(_input_value), do: ""

  defp write_placeholder(%{property: :present_value, type: "REAL"}),
    do: dgettext(BacViewWeb.Gettext, "default", "z. B. 21.5")

  defp write_placeholder(%{type: "BOOLEAN"}),
    do: dgettext(BacViewWeb.Gettext, "default", "true oder false")

  defp write_placeholder(_Gettext), do: dgettext(BacViewWeb.Gettext, "default", "Neuer Wert")

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%d.%m.%Y %H:%M:%S")

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
      hierarchy_path: assigns.return_hierarchy_path
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
end
