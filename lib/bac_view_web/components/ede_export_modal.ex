defmodule BacViewWeb.EdeExportModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:form, :map, required: true)
  attr(:available_types, :list, default: [])
  attr(:devices, :list, default: [])
  attr(:show_devices, :boolean, default: false)
  attr(:id_prefix, :string, default: "ede-export")
  attr(:close_event, :string, default: "close_ede_export_modal")
  attr(:change_event, :string, default: "validate_ede_export")
  attr(:submit_event, :string, default: "export_ede")
  attr(:select_all_types_event, :string, default: "ede_export_select_all_types")
  attr(:select_default_types_event, :string, default: "ede_export_select_default_types")
  attr(:select_all_devices_event, :string, default: "multi_ede_export_select_all_devices")
  attr(:select_no_devices_event, :string, default: "multi_ede_export_select_no_devices")

  def modal(assigns) do
    selected = selected_object_types(assigns.form)
    selected_devices = selected_device_ids(assigns.form)

    assigns =
      assigns
      |> assign(:selected_types, selected)
      |> assign(:selected_count, length(selected))
      |> assign(:available_count, length(assigns.available_types))
      |> assign(:selected_device_ids, selected_devices)
      |> assign(:selected_device_count, length(selected_devices))
      |> assign(:loaded_device_count, Enum.count(assigns.devices, & &1.loaded?))

    ~H"""
    <div id={"#{@id_prefix}-modal"} class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click={@close_event}
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div
        class="bac-modal bac-modal-lg"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id_prefix}-title"}
      >
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "EDE-Export")}
              </p>
              <h2 id={"#{@id_prefix}-title"} class="font-semibold text-base mt-0.5">
                <%= if @show_devices do %>
                  {t(@locale, @locale_version, "EDE für mehrere Geräte")}
                <% else %>
                  {t(@locale, @locale_version, "EDE exportieren")}
                <% end %>
              </h2>
            </div>
            <button
              type="button"
              phx-click={@close_event}
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={@form}
            id={"#{@id_prefix}-form"}
            phx-change={@change_event}
            phx-submit={@submit_event}
            class="space-y-4"
          >
            <fieldset :if={@show_devices} class="space-y-2" id={"#{@id_prefix}-devices"}>
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
                    id={"#{@id_prefix}-select-all-devices"}
                    phx-click={@select_all_devices_event}
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    {t(@locale, @locale_version, "Alle geladenen")}
                  </button>
                  <button
                    type="button"
                    id={"#{@id_prefix}-select-no-devices"}
                    phx-click={@select_no_devices_event}
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    {t(@locale, @locale_version, "Keine")}
                  </button>
                </div>
              </div>
              <p class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Nur geladene Geräte können ausgewählt werden.")}
              </p>
              <input type="hidden" name="ede_export[device_ids][]" value="" />
              <div class="max-h-40 overflow-y-auto rounded-lg border border-[var(--bac-border)] divide-y divide-[var(--bac-border)]">
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
                    name="ede_export[device_ids][]"
                    id={"#{@id_prefix}-device-#{device.id}"}
                    value={device.id}
                    checked={device.id in @selected_device_ids}
                    disabled={!device.loaded?}
                    class="bac-checkbox"
                  />
                  <span class="flex-1 min-w-0 truncate">
                    {device_label(device, @locale, @locale_version)}
                  </span>
                  <span class="bac-mono text-xs bac-text-faint shrink-0">
                    {device.instance}
                  </span>
                  <span class={status_badge_class(device.status)}>
                    {status_label(device.status, @locale, @locale_version)}
                  </span>
                </label>
                <p :if={@devices == []} class="px-3 py-4 text-sm bac-text-muted text-center">
                  {t(@locale, @locale_version, "Keine Geräte vorhanden.")}
                </p>
              </div>
            </fieldset>

            <.input
              field={@form[:project_name]}
              type="text"
              id={"#{@id_prefix}-project-name"}
              label={t(@locale, @locale_version, "Projektname")}
              required
              class="bac-input bac-input-sm w-full"
            />
            <.input
              field={@form[:version]}
              type="text"
              id={"#{@id_prefix}-version"}
              label={t(@locale, @locale_version, "Version")}
              placeholder="1.0.0"
              required
              class="bac-input bac-input-sm w-full"
            />
            <p class="-mt-2 text-xs bac-text-faint">
              {t(@locale, @locale_version, "Semantische Version (MAJOR.MINOR.PATCH), z. B. 1.0.0")}
            </p>
            <.input
              field={@form[:author]}
              type="text"
              id={"#{@id_prefix}-author"}
              label={t(@locale, @locale_version, "Autor")}
              class="bac-input bac-input-sm w-full"
            />

            <fieldset class="space-y-2" id={"#{@id_prefix}-object-types"}>
              <div class="flex items-center justify-between gap-2">
                <legend class="text-sm font-medium text-[var(--bac-text)]">
                  {t(@locale, @locale_version, "Objekttypen")}
                  <span class="font-normal bac-text-faint">
                    ({@selected_count}/{@available_count})
                  </span>
                </legend>
                <div class="flex items-center gap-1">
                  <button
                    type="button"
                    id={"#{@id_prefix}-select-all-types"}
                    phx-click={@select_all_types_event}
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    {t(@locale, @locale_version, "Alle")}
                  </button>
                  <button
                    type="button"
                    id={"#{@id_prefix}-select-default-types"}
                    phx-click={@select_default_types_event}
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    {t(@locale, @locale_version, "Standard")}
                  </button>
                </div>
              </div>
              <p class="text-xs bac-text-faint">
                <%= if @show_devices do %>
                  {t(
                    @locale,
                    @locale_version,
                    "Nur Objekttypen, die auf den ausgewählten Geräten vorhanden sind. Standard: alle ausser Datei und Strukturansicht."
                  )}
                <% else %>
                  {t(
                    @locale,
                    @locale_version,
                    "Nur Objekttypen, die auf dem Gerät vorhanden sind. Standard: alle ausser Datei und Strukturansicht."
                  )}
                <% end %>
              </p>
              <div class="max-h-48 overflow-y-auto rounded-lg border border-[var(--bac-border)] divide-y divide-[var(--bac-border)]">
                <label
                  :for={entry <- @available_types}
                  class="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-[var(--bac-surface-2)]"
                >
                  <input
                    type="checkbox"
                    name="ede_export[object_types][]"
                    id={"#{@id_prefix}-type-#{entry.type}"}
                    value={to_string(entry.type)}
                    checked={entry.type in @selected_types}
                    class="bac-checkbox"
                  />
                  <span class="flex-1 min-w-0 truncate">{entry.label}</span>
                  <span class="bac-mono text-xs bac-text-faint shrink-0">{entry.count}</span>
                </label>
                <p
                  :if={@available_types == []}
                  class="px-3 py-4 text-sm bac-text-muted text-center"
                >
                  {t(@locale, @locale_version, "Keine Objekttypen verfügbar.")}
                </p>
              </div>
            </fieldset>

            <div class="space-y-1.5">
              <.input
                field={@form[:include_state_texts]}
                type="checkbox"
                id={"#{@id_prefix}-include-state-texts"}
                label={t(@locale, @locale_version, "State Texts mit exportieren")}
                class="bac-checkbox"
              />
              <p class="text-xs bac-text-faint pl-7">
                {t(
                  @locale,
                  @locale_version,
                  "Erzeugt zusätzlich eine StateTexts-CSV und verknüpft Binär-/Multistate-Objekte."
                )}
              </p>
            </div>

            <div class="flex items-center justify-end gap-2 pt-1">
              <button
                type="button"
                phx-click={@close_event}
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                class="bac-btn bac-btn-primary bac-btn-sm"
                id={"#{@id_prefix}-submit"}
                disabled={@selected_count == 0 or (@show_devices and @selected_device_count == 0)}
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

  defp selected_object_types(%{params: params}) when is_map(params) do
    parse_selected_types(Map.get(params, "object_types") || Map.get(params, :object_types))
  end

  defp selected_object_types(%{source: source}) when is_map(source) do
    parse_selected_types(Map.get(source, "object_types") || Map.get(source, :object_types))
  end

  defp selected_object_types(_form), do: []

  defp selected_device_ids(%{params: params}) when is_map(params) do
    parse_device_ids(Map.get(params, "device_ids") || Map.get(params, :device_ids))
  end

  defp selected_device_ids(%{source: source}) when is_map(source) do
    parse_device_ids(Map.get(source, "device_ids") || Map.get(source, :device_ids))
  end

  defp selected_device_ids(_form), do: []

  defp parse_selected_types(nil), do: []
  defp parse_selected_types(types) when is_list(types), do: Enum.map(types, &parse_type/1)
  defp parse_selected_types(type), do: [parse_type(type)]

  defp parse_type(type) when is_atom(type), do: type
  defp parse_type(type) when is_integer(type), do: type

  defp parse_type(type) when is_binary(type) do
    case Integer.parse(type) do
      {int, ""} ->
        int

      _other ->
        try do
          String.to_existing_atom(type)
        rescue
          ArgumentError -> type
        end
    end
  end

  defp parse_type(type), do: type

  defp parse_device_ids(nil), do: []

  defp parse_device_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_device_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_device_ids(id), do: parse_device_ids([id])

  defp parse_device_id(id) when is_integer(id) and id >= 0, do: id

  defp parse_device_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {int, ""} when int >= 0 -> int
      _other -> nil
    end
  end

  defp parse_device_id(_id), do: nil
end
