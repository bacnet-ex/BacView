defmodule BacViewWeb.EdeExportModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:form, :map, required: true)
  attr(:available_types, :list, default: [])

  def modal(assigns) do
    selected = selected_object_types(assigns.form)

    assigns =
      assigns
      |> assign(:selected_types, selected)
      |> assign(:selected_count, length(selected))
      |> assign(:available_count, length(assigns.available_types))

    ~H"""
    <div id="ede-export-modal" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_ede_export_modal"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div
        class="bac-modal bac-modal-lg"
        role="dialog"
        aria-modal="true"
        aria-labelledby="ede-export-title"
      >
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "EDE-Export")}
              </p>
              <h2 id="ede-export-title" class="font-semibold text-base mt-0.5">
                {t(@locale, @locale_version, "EDE exportieren")}
              </h2>
            </div>
            <button
              type="button"
              phx-click="close_ede_export_modal"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={@form}
            id="ede-export-form"
            phx-change="validate_ede_export"
            phx-submit="export_ede"
            class="space-y-4"
          >
            <.input
              field={@form[:project_name]}
              type="text"
              id="ede-export-project-name"
              label={t(@locale, @locale_version, "Projektname")}
              required
              class="bac-input bac-input-sm w-full"
            />
            <.input
              field={@form[:version]}
              type="text"
              id="ede-export-version"
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
              id="ede-export-author"
              label={t(@locale, @locale_version, "Autor")}
              class="bac-input bac-input-sm w-full"
            />

            <fieldset class="space-y-2" id="ede-export-object-types">
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
                    id="ede-export-select-all-types"
                    phx-click="ede_export_select_all_types"
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    {t(@locale, @locale_version, "Alle")}
                  </button>
                  <button
                    type="button"
                    id="ede-export-select-default-types"
                    phx-click="ede_export_select_default_types"
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    {t(@locale, @locale_version, "Standard")}
                  </button>
                </div>
              </div>
              <p class="text-xs bac-text-faint">
                {t(
                  @locale,
                  @locale_version,
                  "Nur Objekttypen, die auf dem Gerät vorhanden sind. Standard: alle ausser Datei und Strukturansicht."
                )}
              </p>
              <div class="max-h-48 overflow-y-auto rounded-lg border border-[var(--bac-border)] divide-y divide-[var(--bac-border)]">
                <label
                  :for={entry <- @available_types}
                  class="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-[var(--bac-surface-2)]"
                >
                  <input
                    type="checkbox"
                    name="ede_export[object_types][]"
                    id={"ede-export-type-#{entry.type}"}
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
                id="ede-export-include-state-texts"
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
                phx-click="close_ede_export_modal"
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                class="bac-btn bac-btn-primary bac-btn-sm"
                id="ede-export-submit"
                disabled={@selected_count == 0}
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

  defp selected_object_types(%{params: params}) when is_map(params) do
    parse_selected_types(Map.get(params, "object_types") || Map.get(params, :object_types))
  end

  defp selected_object_types(%{source: source}) when is_map(source) do
    parse_selected_types(Map.get(source, "object_types") || Map.get(source, :object_types))
  end

  defp selected_object_types(_form), do: []

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
end
