defmodule BacViewWeb.WritePropertyModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacViewWeb.PropertyValue

  attr(:object, :map, required: true)
  attr(:property, :map, required: true)
  attr(:editor_mode, :atom, default: :fields)
  attr(:form_fields, :list, default: [])
  attr(:draft_fields, :map, default: %{})
  attr(:draft_json, :string, required: true)
  attr(:field_error, :string, default: nil)
  attr(:json_error, :string, default: nil)
  attr(:submit_error, :string, default: nil)
  attr(:write_priority, :integer, default: 8)
  attr(:writing, :boolean, default: false)

  def modal(assigns) do
    ~H"""
    <div id="write-property-modal" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_write_property_modal"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal bac-modal-lg" role="dialog" aria-modal="true">
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "Eigenschaft schreiben")}
              </p>
              <h2 class="font-semibold text-base truncate mt-0.5">
                {@property.property_name}
              </h2>
              <p class="bac-mono text-xs bac-text-faint mt-0.5">
                {@object.name || "#{@object.type}:#{@object.instance}"}
              </p>
            </div>
            <button
              type="button"
              phx-click="close_write_property_modal"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <div class="bac-stat py-3">
            <p class="bac-stat-label">{t(@locale, @locale_version, "Aktueller Wert")}</p>
            <div class="bac-stat-value text-sm mt-1">
              <PropertyValue.property_value
                display={@property.value_display}
                writable={false}
                property={@property.property}
                dom_id_prefix="modal"
                locale={@locale}
                locale_version={@locale_version}
              />
            </div>
          </div>

          <div class="flex gap-1 rounded-lg border border-base-300/40 p-1 bg-base-200/30">
            <button
              type="button"
              id="write-property-mode-fields"
              class={[
                "flex-1 bac-btn bac-btn-sm",
                if(@editor_mode == :fields, do: "bac-btn-primary", else: "bac-btn-ghost")
              ]}
              phx-click="toggle_write_property_editor"
              phx-value-mode="fields"
            >
              <.icon name="hero-list-bullet" class="size-3.5" />
              {t(@locale, @locale_version, "Felder")}
            </button>
            <button
              type="button"
              id="write-property-mode-json"
              class={[
                "flex-1 bac-btn bac-btn-sm",
                if(@editor_mode == :json, do: "bac-btn-primary", else: "bac-btn-ghost")
              ]}
              phx-click="toggle_write_property_editor"
              phx-value-mode="json"
            >
              <.icon name="hero-code-bracket" class="size-3.5" />
              {t(@locale, @locale_version, "JSON")}
            </button>
          </div>

          <%= if @editor_mode == :fields do %>
            <form
              id="write-property-fields-form"
              phx-change="change_write_property_fields"
              class="space-y-3"
            >
              <%= if @form_fields == [] do %>
                <p class="text-sm bac-text-faint">
                  {t(
                    @locale,
                    @locale_version,
                    "Keine bearbeitbaren Felder für diesen Wert. Wechseln Sie zu JSON."
                  )}
                </p>
              <% else %>
                <div class="space-y-2 max-h-[40vh] overflow-y-auto pr-1">
                  <%= for field <- @form_fields do %>
                    <div class="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-3">
                      <label
                        for={field_dom_id(field.path)}
                        class="sm:w-2/5 shrink-0 text-xs bac-mono bac-text-faint truncate"
                        title={field.path}
                      >
                        {field.label}
                      </label>
                      <select
                        :if={field.enum_options}
                        id={field_dom_id(field.path)}
                        name={"field[#{field.path}]"}
                        class="flex-1 bac-input bac-input-sm text-xs min-w-0"
                        disabled={field_disabled?(@draft_fields, field, @writing)}
                        phx-debounce="300"
                      >
                        <option
                          :for={opt <- field.enum_options}
                          value={Atom.to_string(opt.value)}
                          selected={enum_field_selected?(@draft_fields, field, opt)}
                        >
                          {opt.label}
                        </option>
                      </select>
                      <input
                        :if={!field.enum_options}
                        id={field_dom_id(field.path)}
                        name={"field[#{field.path}]"}
                        type="text"
                        value={Map.get(@draft_fields, field.path, field.value)}
                        class="flex-1 bac-input bac-input-sm bac-mono text-xs"
                        disabled={field_disabled?(@draft_fields, field, @writing)}
                        phx-debounce="300"
                      />
                    </div>
                  <% end %>
                </div>
              <% end %>
            </form>
            <p :if={@field_error} class="text-sm text-error">{@field_error}</p>
          <% else %>
            <form id="write-property-json-form" phx-change="change_write_property_json">
              <div class="space-y-1.5">
                <label for="write-property-json" class="text-xs bac-text-faint">
                  {t(@locale, @locale_version, "Neuer Wert (JSON)")}
                </label>
                <textarea
                  id="write-property-json"
                  name="json"
                  rows="14"
                  class={[
                    "bac-input bac-mono w-full text-xs leading-relaxed",
                    @json_error && "border-error"
                  ]}
                  disabled={@writing}
                  phx-debounce="300"
                >{@draft_json}</textarea>
                <p class="text-xs bac-text-faint">
                  {t(
                    @locale,
                    @locale_version,
                    "Erweitert: Struktur als JSON bearbeiten. Feldnamen müssen unverändert bleiben."
                  )}
                </p>
              </div>
            </form>
            <p :if={@json_error} class="text-sm text-error">{@json_error}</p>
          <% end %>

          <div
            :if={@submit_error}
            id="write-property-submit-error"
            class="bac-alert bac-alert-error"
            role="alert"
          >
            <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
            <span class="text-sm">{@submit_error}</span>
          </div>

          <div class="flex flex-wrap items-center justify-end gap-2 pt-2">
            <button
              type="button"
              phx-click="close_write_property_modal"
              class="bac-btn bac-btn-ghost bac-btn-sm"
            >
              {t(@locale, @locale_version, "Abbrechen")}
            </button>
            <button
              type="button"
              id="write-property-submit"
              phx-click="write_property_modal"
              disabled={@writing or editor_submit_disabled?(@editor_mode, @field_error, @json_error, @form_fields)}
              class="bac-btn bac-btn-primary bac-btn-sm"
            >
              <.icon :if={@writing} name="hero-arrow-path" class="size-4 animate-spin" />
              {t(@locale, @locale_version, "Schreiben")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp field_dom_id(path) do
    "write-field-" <> String.replace(path, ".", "-")
  end

  defp field_disabled?(draft_fields, %{path: "extras.tag_number"}, writing),
    do: writing or encoding_kind(draft_fields) == "primitive"

  defp field_disabled?(_draft_fields, _field, writing), do: writing

  defp encoding_kind(draft_fields) do
    draft_fields
    |> Map.get("encoding", "primitive")
    |> to_string()
  end

  defp enum_field_selected?(draft_fields, field, opt) do
    Map.get(draft_fields, field.path, field.value) == Atom.to_string(opt.value)
  end

  defp editor_submit_disabled?(:fields, field_error, _json_error, form_fields) do
    field_error != nil or form_fields == []
  end

  defp editor_submit_disabled?(:json, _field_error, json_error, _form_fields) do
    json_error != nil
  end
end
