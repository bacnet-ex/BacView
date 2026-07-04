defmodule BacViewWeb.WriteWeeklyScheduleModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.WeeklyScheduleEditor
  alias BacViewWeb.PropertyValue

  attr(:object, :map, required: true)
  attr(:property, :map, required: true)
  attr(:mode, :atom, default: :weekdays)
  attr(:active_day, :integer, default: 1)
  attr(:draft, :map, required: true)
  attr(:value_kind, :any, required: true)
  attr(:draft_json, :string, required: true)
  attr(:field_error, :string, default: nil)
  attr(:json_error, :string, default: nil)
  attr(:submit_error, :string, default: nil)
  attr(:write_priority, :integer, default: 8)
  attr(:writing, :boolean, default: false)

  def modal(assigns) do
    assigns =
      assign(assigns, :active_day_data, active_day_data(assigns.draft, assigns.active_day))

    assigns =
      assign(assigns, :enum_options, WeeklyScheduleEditor.enum_options(assigns.value_kind))

    ~H"""
    <div id="write-weekly-schedule-modal" class="bac-modal-backdrop">
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
                {t(@locale, @locale_version, "Wochenplan bearbeiten")}
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
              id="weekly-schedule-mode-weekdays"
              class={[
                "flex-1 bac-btn bac-btn-sm",
                if(@mode == :weekdays, do: "bac-btn-primary", else: "bac-btn-ghost")
              ]}
              phx-click="toggle_weekly_schedule_mode"
              phx-value-mode="weekdays"
            >
              <.icon name="hero-calendar-days" class="size-3.5" />
              {t(@locale, @locale_version, "Wochentage")}
            </button>
            <button
              type="button"
              id="weekly-schedule-mode-json"
              class={[
                "flex-1 bac-btn bac-btn-sm",
                if(@mode == :json, do: "bac-btn-primary", else: "bac-btn-ghost")
              ]}
              phx-click="toggle_weekly_schedule_mode"
              phx-value-mode="json"
            >
              <.icon name="hero-code-bracket" class="size-3.5" />
              {t(@locale, @locale_version, "JSON")}
            </button>
          </div>

          <%= if @mode == :weekdays do %>
            <div class="bac-tabs">
              <%= for day <- WeeklyScheduleEditor.draft_days(@draft) do %>
                <button
                  type="button"
                  id={"weekly-day-tab-#{day.index}"}
                  class={["bac-tab", @active_day == day.index && "bac-tab-active"]}
                  phx-click="weekly_schedule_select_day"
                  phx-value-day={day.index}
                >
                  {day.label}
                  <span
                    :if={day.entries != []}
                    class="bac-badge bac-badge-sm bac-badge-ghost ml-1"
                  >
                    {length(day.entries)}
                  </span>
                </button>
              <% end %>
            </div>

            <form
              id="weekly-schedule-day-form"
              phx-change="change_weekly_schedule"
              class="space-y-3"
            >
              <div class="flex items-center justify-between gap-3">
                <h3 class="text-sm font-medium">{@active_day_data.label}</h3>
                <button
                  type="button"
                  id="weekly-schedule-add-entry"
                  class="bac-btn bac-btn-ghost bac-btn-xs"
                  phx-click="weekly_schedule_add_entry"
                  disabled={@writing}
                >
                  <.icon name="hero-plus" class="size-3.5" />
                  {t(@locale, @locale_version, "Zeitfenster hinzufügen")}
                </button>
              </div>

              <div :if={@active_day_data.entries == []} class="bac-hero py-10">
                <p class="bac-hero-text text-sm">
                  {t(@locale, @locale_version, "Keine Zeitfenster für diesen Tag")}
                </p>
              </div>

              <div :if={@active_day_data.entries != []} class="space-y-2 max-h-[40vh] overflow-y-auto pr-1">
                <%= for {entry, index} <- Enum.with_index(@active_day_data.entries) do %>
                  <div
                    id={"weekly-entry-#{entry.id}"}
                    class="grid grid-cols-[1fr_1fr_auto] gap-2 items-center rounded-lg border border-base-300/30 p-2"
                  >
                    <input type="hidden" name={"entries[#{index}][id]"} value={entry.id} />
                    <div class="space-y-1">
                      <label
                        for={"weekly-entry-time-#{entry.id}"}
                        class="text-xs bac-text-faint"
                      >
                        {t(@locale, @locale_version, "Zeit")}
                      </label>
                      <input
                        id={"weekly-entry-time-#{entry.id}"}
                        name={"entries[#{index}][time]"}
                        type="time"
                        step="0.01"
                        value={entry.time}
                        class="bac-input bac-input-sm w-full"
                        disabled={@writing}
                        phx-debounce="300"
                      />
                    </div>
                    <div class="space-y-1">
                      <label
                        for={"weekly-entry-value-#{entry.id}"}
                        class="text-xs bac-text-faint"
                      >
                        {t(@locale, @locale_version, "Wert")}
                      </label>
                      <select
                        :if={@enum_options}
                        id={"weekly-entry-value-#{entry.id}"}
                        name={"entries[#{index}][value]"}
                        class="bac-input bac-input-sm w-full"
                        disabled={@writing}
                        phx-debounce="300"
                      >
                        <option
                          :for={opt <- @enum_options}
                          value={Atom.to_string(opt.value)}
                          selected={entry.value == Atom.to_string(opt.value)}
                        >
                          {opt.label}
                        </option>
                      </select>
                      <select
                        :if={@value_kind == :boolean and !@enum_options}
                        id={"weekly-entry-value-#{entry.id}"}
                        name={"entries[#{index}][value]"}
                        class="bac-input bac-input-sm w-full"
                        disabled={@writing}
                        phx-debounce="300"
                      >
                        <option value="true" selected={entry.value == "true"}>true</option>
                        <option value="false" selected={entry.value == "false"}>false</option>
                      </select>
                      <input
                        :if={@value_kind != :boolean and !@enum_options}
                        id={"weekly-entry-value-#{entry.id}"}
                        name={"entries[#{index}][value]"}
                        type={if(@value_kind in [:real, :unsigned_integer], do: "number", else: "text")}
                        step={weekly_entry_value_step(@value_kind)}
                        min={if(@value_kind == :unsigned_integer, do: "0", else: nil)}
                        value={entry.value}
                        class="bac-input bac-input-sm w-full"
                        disabled={@writing}
                        phx-debounce="300"
                      />
                    </div>
                    <button
                      type="button"
                      id={"weekly-entry-remove-#{entry.id}"}
                      class="bac-btn bac-btn-ghost bac-btn-icon bac-btn-xs self-end"
                      phx-click="weekly_schedule_remove_entry"
                      phx-value-entry_id={entry.id}
                      disabled={@writing}
                      aria-label={t(@locale, @locale_version, "Zeitfenster entfernen")}
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </div>
                <% end %>
              </div>
            </form>
            <p :if={@field_error} class="text-sm text-error">{@field_error}</p>
          <% else %>
            <form id="weekly-schedule-json-form" phx-change="change_weekly_schedule_json">
              <div class="space-y-1.5">
                <label for="weekly-schedule-json" class="text-xs bac-text-faint">
                  {t(@locale, @locale_version, "Neuer Wert (JSON)")}
                </label>
                <textarea
                  id="weekly-schedule-json"
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
                    "Erweitert: 7 Tageseinträge als JSON. Die Anzahl der Elemente muss 7 bleiben."
                  )}
                </p>
              </div>
            </form>
            <p :if={@json_error} class="text-sm text-error">{@json_error}</p>
          <% end %>

          <div
            :if={@submit_error}
            id="weekly-schedule-submit-error"
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
              id="weekly-schedule-submit"
              phx-click="write_property_modal"
              disabled={@writing or submit_disabled?(@mode, @field_error, @json_error)}
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

  defp active_day_data(draft, active_day) do
    days = WeeklyScheduleEditor.draft_days(draft)

    Enum.find(days, &(&1.index == active_day)) ||
      List.first(days) ||
      %{index: active_day, label: "", entries: []}
  end

  defp submit_disabled?(:weekdays, field_error, _json_error), do: field_error != nil
  defp submit_disabled?(:json, _field_error, json_error), do: json_error != nil

  defp weekly_entry_value_step(:real), do: "any"
  defp weekly_entry_value_step(:unsigned_integer), do: "1"
  defp weekly_entry_value_step(_real), do: nil
end
