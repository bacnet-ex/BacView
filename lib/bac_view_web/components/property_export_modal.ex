defmodule BacViewWeb.PropertyExportModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.PropertyExport

  attr(:form, :map, required: true)
  attr(:devices, :list, default: [])
  attr(:objects, :list, default: [])
  attr(:available_properties, :list, default: [])

  def modal(assigns) do
    selected_devices = selected_device_ids(assigns.form)
    selected_keys = string_list(assigns.form, "object_keys")
    selected_properties = string_list(assigns.form, "property_ids")
    filter = string_value(assigns.form, "object_type")
    object_query = string_value(assigns.form, "object_query")
    property_query = string_value(assigns.form, "property_query")
    visible = PropertyExport.filter_objects(assigns.objects, filter, object_query)
    visible_keys = MapSet.new(visible, & &1.key)
    hidden_keys = Enum.filter(selected_keys, &(&1 not in visible_keys))

    visible_properties =
      PropertyExport.filter_properties(assigns.available_properties, property_query)

    visible_property_tokens = MapSet.new(visible_properties, & &1.token)

    hidden_property_tokens =
      Enum.filter(selected_properties, &(&1 not in visible_property_tokens))

    type_options = type_options(assigns.objects)
    device_count = assigns.objects |> Enum.uniq_by(& &1.device_id) |> length()
    multiple_devices? = device_count > 1

    assigns =
      assigns
      |> assign(:selected_device_ids, selected_devices)
      |> assign(:selected_device_count, length(selected_devices))
      |> assign(:loaded_device_count, Enum.count(assigns.devices, & &1.loaded?))
      |> assign(:selected_keys, selected_keys)
      |> assign(:selected_object_count, length(selected_keys))
      |> assign(:object_count, length(assigns.objects))
      |> assign(:visible_objects, visible)
      |> assign(:hidden_keys, hidden_keys)
      |> assign(:object_query, object_query)
      |> assign(:visible_properties, visible_properties)
      |> assign(:hidden_property_tokens, hidden_property_tokens)
      |> assign(:property_query, property_query)
      |> assign(:selected_properties, selected_properties)
      |> assign(:selected_property_count, length(selected_properties))
      |> assign(:property_count, length(assigns.available_properties))
      |> assign(:filter, filter)
      |> assign(:type_options, type_options)
      |> assign(:format, string_value(assigns.form, "format"))
      |> assign(:multiple_devices?, multiple_devices?)

    ~H"""
    <div id="property-export-modal" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_property_export"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div
        class="bac-modal bac-modal-xl"
        role="dialog"
        aria-modal="true"
        aria-labelledby="property-export-title"
      >
        <div class="bac-modal-body flex flex-col gap-4 min-h-0">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "Eigenschaften exportieren")}
              </p>
              <h2 id="property-export-title" class="font-semibold text-base mt-0.5">
                {t(@locale, @locale_version, "Eigenschaften für mehrere Geräte")}
              </h2>
              <p class="text-xs bac-text-faint mt-1">
                {t(
                  @locale,
                  @locale_version,
                  "CSV oder JSON der Objekteigenschaften geladener Geräte."
                )}
              </p>
            </div>
            <button
              type="button"
              phx-click="close_property_export"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={@form}
            id="property-export-form"
            phx-change="validate_property_export"
            phx-submit="export_properties"
            class="flex flex-col gap-4 min-h-0"
          >
            <div class="min-h-0 overflow-y-auto space-y-4 pr-1 max-h-[calc(100dvh-14rem)]">
              <fieldset class="space-y-2" id="property-export-format">
                <legend class="text-sm font-medium text-[var(--bac-text)]">
                  {t(@locale, @locale_version, "Format")}
                </legend>
                <div class="flex flex-wrap items-center gap-4">
                  <label class="flex items-center gap-2 text-sm cursor-pointer">
                    <input
                      type="radio"
                      id="property-export-format-csv"
                      name="property_export[format]"
                      value="csv"
                      checked={@format != "json"}
                      class="bac-checkbox"
                    />
                    <span>{t(@locale, @locale_version, "CSV")}</span>
                  </label>
                  <label class="flex items-center gap-2 text-sm cursor-pointer">
                    <input
                      type="radio"
                      id="property-export-format-json"
                      name="property_export[format]"
                      value="json"
                      checked={@format == "json"}
                      class="bac-checkbox"
                    />
                    <span>{t(@locale, @locale_version, "JSON")}</span>
                  </label>
                </div>
              </fieldset>

              <fieldset class="space-y-2" id="property-export-devices">
                <div class="flex items-center justify-between gap-2">
                  <legend class="text-sm font-medium text-[var(--bac-text)]">
                    {t(@locale, @locale_version, "Geräte")}
                    <span class="font-normal bac-text-faint">
                      ({@selected_device_count}/{@loaded_device_count})
                    </span>
                  </legend>
                  <div class="flex items-center gap-1">
                    <button
                      type="button"
                      id="property-export-select-all-devices"
                      phx-click="property_export_select_all_devices"
                      class="bac-btn bac-btn-ghost bac-btn-xs"
                    >
                      {t(@locale, @locale_version, "Alle geladenen")}
                    </button>
                    <button
                      type="button"
                      id="property-export-select-no-devices"
                      phx-click="property_export_select_no_devices"
                      class="bac-btn bac-btn-ghost bac-btn-xs"
                    >
                      {t(@locale, @locale_version, "Keine")}
                    </button>
                  </div>
                </div>
                <p class="text-xs bac-text-faint">
                  {t(@locale, @locale_version, "Nur geladene Geräte können ausgewählt werden.")}
                </p>
                <input type="hidden" name="property_export[device_ids][]" value="" />
                <div class="max-h-36 overflow-y-auto rounded-lg border border-[var(--bac-border)] divide-y divide-[var(--bac-border)]">
                  <label
                    :for={device <- @devices}
                    class={[
                      "flex items-center gap-2 px-3 py-2 text-sm",
                      device.loaded? && "cursor-pointer hover:bg-[var(--bac-surface-2)]",
                      not device.loaded? && "opacity-60 cursor-not-allowed"
                    ]}
                  >
                    <input
                      type="checkbox"
                      name="property_export[device_ids][]"
                      id={"property-export-device-#{device.id}"}
                      value={device.id}
                      checked={device.id in @selected_device_ids}
                      disabled={!device.loaded?}
                      class="bac-checkbox"
                    />
                    <span class="flex-1 min-w-0 truncate">
                      {device_label(device, @locale, @locale_version)}
                    </span>
                    <span class="bac-mono text-xs bac-text-faint shrink-0">{device.instance}</span>
                    <span class={status_badge_class(device.status)}>
                      {status_label(device.status, @locale, @locale_version)}
                    </span>
                  </label>
                  <p :if={@devices == []} class="px-3 py-4 text-sm bac-text-muted text-center">
                    {t(@locale, @locale_version, "Keine Geräte vorhanden.")}
                  </p>
                </div>
              </fieldset>

              <div class="grid gap-4 lg:grid-cols-2">
                <fieldset class="space-y-2 min-w-0" id="property-export-objects">
                  <div class="flex items-center justify-between gap-2">
                    <legend class="text-sm font-medium text-[var(--bac-text)]">
                      {t(@locale, @locale_version, "Objekte")}
                      <span class="font-normal bac-text-faint">
                        ({@selected_object_count}/{@object_count})
                      </span>
                    </legend>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        id="property-export-select-all-objects"
                        phx-click="property_export_select_all_objects"
                        class="bac-btn bac-btn-ghost bac-btn-xs"
                      >
                        {t(@locale, @locale_version, "Alle sichtbaren")}
                      </button>
                      <button
                        type="button"
                        id="property-export-select-no-objects"
                        phx-click="property_export_select_no_objects"
                        class="bac-btn bac-btn-ghost bac-btn-xs"
                      >
                        {t(@locale, @locale_version, "Keine sichtbaren")}
                      </button>
                    </div>
                  </div>
                  <label class="bac-label" for="property-export-type-filter">
                    {t(@locale, @locale_version, "Objekttyp")}
                  </label>
                  <select
                    id="property-export-type-filter"
                    name="property_export[object_type]"
                    class="bac-input bac-input-sm w-full"
                  >
                    <option value="" selected={@filter == ""}>
                      {t(@locale, @locale_version, "Alle Typen")}
                    </option>
                    <option
                      :for={type <- @type_options}
                      value={type.token}
                      selected={@filter == type.token}
                    >
                      {type.label} ({type.count})
                    </option>
                  </select>
                  <p class="text-xs bac-text-faint">
                    {t(
                      @locale,
                      @locale_version,
                      "Auswahl gilt für die angezeigten Objekte. Nicht sichtbare, bereits gewählte Objekte bleiben ausgewählt."
                    )}
                  </p>
                  <label class="bac-label" for="property-export-object-search">
                    {t(@locale, @locale_version, "Suche")}
                  </label>
                  <input
                    type="search"
                    id="property-export-object-search"
                    name="property_export[object_query]"
                    value={@object_query}
                    placeholder={t(@locale, @locale_version, "Objekte suchen…")}
                    phx-debounce="200"
                    autocomplete="off"
                    class="bac-input bac-input-sm w-full"
                  />
                  <input type="hidden" name="property_export[object_keys][]" value="" />
                  <input
                    :for={key <- @hidden_keys}
                    type="hidden"
                    id={"property-export-hidden-object-#{dom_key(key)}"}
                    name="property_export[object_keys][]"
                    value={key}
                  />
                  <div class="max-h-64 overflow-y-auto rounded-lg border border-[var(--bac-border)] divide-y divide-[var(--bac-border)]">
                    <label
                      :for={object <- @visible_objects}
                      class="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-[var(--bac-surface-2)]"
                    >
                      <input
                        type="checkbox"
                        name="property_export[object_keys][]"
                        id={"property-export-object-#{dom_key(object.key)}"}
                        value={object.key}
                        checked={object.key in @selected_keys}
                        class="bac-checkbox"
                      />
                      <span class="flex-1 min-w-0 truncate">
                        {object_label(object, @multiple_devices?)}
                      </span>
                      <span class="bac-mono text-xs bac-text-faint shrink-0">{object.instance}</span>
                    </label>
                    <p
                      :if={@visible_objects == []}
                      class="px-3 py-4 text-sm bac-text-muted text-center"
                    >
                      <%= if @object_count == 0 do %>
                        {t(@locale, @locale_version, "Keine Objekte für die aktuelle Auswahl.")}
                      <% else %>
                        {t(@locale, @locale_version, "Keine passenden Objekte.")}
                      <% end %>
                    </p>
                  </div>
                </fieldset>

                <fieldset class="space-y-2 min-w-0" id="property-export-properties">
                  <div class="flex items-center justify-between gap-2">
                    <legend class="text-sm font-medium text-[var(--bac-text)]">
                      {t(@locale, @locale_version, "Eigenschaften")}
                      <span class="font-normal bac-text-faint">
                        ({@selected_property_count}/{@property_count})
                      </span>
                    </legend>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        id="property-export-select-all-properties"
                        phx-click="property_export_select_all_properties"
                        class="bac-btn bac-btn-ghost bac-btn-xs"
                      >
                        {t(@locale, @locale_version, "Alle sichtbaren")}
                      </button>
                      <button
                        type="button"
                        id="property-export-select-no-properties"
                        phx-click="property_export_select_no_properties"
                        class="bac-btn bac-btn-ghost bac-btn-xs"
                      >
                        {t(@locale, @locale_version, "Keine sichtbaren")}
                      </button>
                    </div>
                  </div>
                  <p class="text-xs bac-text-faint">
                    {t(
                      @locale,
                      @locale_version,
                      "Eigenschaften der ausgewählten Objekte. Fehlt eine Eigenschaft beim Objekt, bleibt das Feld leer (CSV) bzw. null (JSON)."
                    )}
                  </p>
                  <label class="bac-label" for="property-export-property-search">
                    {t(@locale, @locale_version, "Suche")}
                  </label>
                  <input
                    type="search"
                    id="property-export-property-search"
                    name="property_export[property_query]"
                    value={@property_query}
                    placeholder={t(@locale, @locale_version, "Eigenschaften suchen…")}
                    phx-debounce="200"
                    autocomplete="off"
                    class="bac-input bac-input-sm w-full"
                  />
                  <input type="hidden" name="property_export[property_ids][]" value="" />
                  <input
                    :for={token <- @hidden_property_tokens}
                    type="hidden"
                    id={"property-export-hidden-property-#{token}"}
                    name="property_export[property_ids][]"
                    value={token}
                  />
                  <div class="max-h-72 overflow-y-auto rounded-lg border border-[var(--bac-border)] divide-y divide-[var(--bac-border)]">
                    <label
                      :for={property <- @visible_properties}
                      class="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-[var(--bac-surface-2)]"
                    >
                      <input
                        type="checkbox"
                        name="property_export[property_ids][]"
                        id={"property-export-property-#{property.token}"}
                        value={property.token}
                        checked={property.token in @selected_properties}
                        class="bac-checkbox"
                      />
                      <span class="flex-1 min-w-0 truncate">{property.label}</span>
                      <span class="bac-mono text-xs bac-text-faint shrink-0">{property.token}</span>
                    </label>
                    <p
                      :if={@visible_properties == []}
                      class="px-3 py-4 text-sm bac-text-muted text-center"
                    >
                      <%= if @available_properties == [] do %>
                        {t(@locale, @locale_version, "Keine Eigenschaften verfügbar.")}
                      <% else %>
                        {t(@locale, @locale_version, "Keine passenden Eigenschaften.")}
                      <% end %>
                    </p>
                  </div>
                </fieldset>
              </div>
            </div>

            <div class="flex items-center justify-end gap-2">
              <button
                type="button"
                phx-click="close_property_export"
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                class="bac-btn bac-btn-primary bac-btn-sm"
                id="property-export-submit"
                disabled={
                  @selected_device_count == 0 or @selected_object_count == 0 or
                    @selected_property_count == 0
                }
              >
                {t(@locale, @locale_version, "Exportieren")}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp type_options(objects) do
    objects
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, entries} ->
      %{
        type: type,
        token: PropertyExport.property_token(type),
        label: entries |> List.first() |> Map.get(:type_label),
        count: length(entries)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.label || ""))
  end

  defp object_label(object, multiple_devices?) do
    base =
      case object.name do
        name when is_binary(name) and name != "" ->
          "#{object.type_label} #{object.instance} · #{name}"

        _name ->
          "#{object.type_label} #{object.instance}"
      end

    if multiple_devices? do
      prefix = object.device_name || Integer.to_string(object.device_instance)
      "#{prefix} · #{base}"
    else
      base
    end
  end

  defp dom_key(key) when is_binary(key), do: String.replace(key, "|", "-")

  defp device_label(%{name: name}, _locale, _locale_version) when is_binary(name) and name != "",
    do: name

  defp device_label(%{instance: instance}, locale, locale_version),
    do: t(locale, locale_version, "Gerät %{id}", id: instance)

  defp status_label(:loaded, locale, locale_version),
    do: t(locale, locale_version, "Geladen")

  defp status_label(:loading, locale, locale_version),
    do: t(locale, locale_version, "Wird geladen")

  defp status_label(:discovered, locale, locale_version),
    do: t(locale, locale_version, "Entdeckt")

  defp status_label(_status, locale, locale_version),
    do: t(locale, locale_version, "Unbekannt")

  defp status_badge_class(:loaded),
    do: ["bac-badge bac-badge-sm shrink-0", "bac-badge-success"]

  defp status_badge_class(:loading),
    do: ["bac-badge bac-badge-sm shrink-0", "bac-badge-warning"]

  defp status_badge_class(_status),
    do: ["bac-badge bac-badge-sm shrink-0", "bac-badge-ghost"]

  defp string_list(form, key) do
    form
    |> form_value(key)
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp string_value(form, key) do
    case form_value(form, key) do
      value when is_binary(value) -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _value -> ""
    end
  end

  defp form_value(%{params: params}, key) when is_map(params) and map_size(params) > 0 do
    map_value(params, key)
  end

  defp form_value(%{source: source}, key) when is_map(source) do
    map_value(source, key)
  end

  defp form_value(_form, _key), do: nil

  defp map_value(params, key) do
    atom_key =
      Enum.find(Map.keys(params), fn existing ->
        is_atom(existing) and Atom.to_string(existing) == key
      end)

    Map.get(params, key) || Map.get(params, atom_key)
  end

  defp selected_device_ids(form) do
    form
    |> string_list("device_ids")
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {int, ""} when int >= 0 -> [int]
        _other -> []
      end
    end)
  end
end
