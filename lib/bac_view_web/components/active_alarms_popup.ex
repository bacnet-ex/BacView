defmodule BacViewWeb.ActiveAlarmsPopup do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:count, :integer, required: true)
  attr(:open, :boolean, default: false)
  attr(:show_device_label, :boolean, default: false)

  def active_alarms_badge(assigns) do
    ~H"""
    <button
      :if={@count > 0}
      type="button"
      id="active-alarms-badge"
      phx-click="toggle_alarm_popup"
      class={[
        "bac-badge bac-badge-error cursor-pointer transition-all",
        "hover:ring-2 hover:ring-[var(--bac-rose)]/40",
        @open && "ring-2 ring-[var(--bac-rose)]/50"
      ]}
      aria-expanded={to_string(@open)}
      aria-haspopup="dialog"
    >
      <.icon name="hero-bell-alert" class="size-3" />
      {@count}
      <span :if={@show_device_label} class="normal-case tracking-normal">
        {t(@locale, @locale_version, "Alarme")}
      </span>
    </button>
    """
  end

  attr(:open, :boolean, default: false)
  attr(:entries, :list, default: [])
  attr(:show_device, :boolean, default: true)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def active_alarms_panel(assigns) do
    ~H"""
    <div
      :if={@open}
      id="active-alarms-popup"
      phx-hook="FilterMenu"
      data-trigger-id="active-alarms-badge"
      data-close-event="close_alarm_popup"
      class="bac-alarm-popup bac-filter-menu--floating"
      role="dialog"
      aria-label={t(@locale, @locale_version, "Aktive Alarme")}
    >
      <div class="bac-alarm-popup-header">
        <p class="text-xs font-semibold text-[var(--bac-text)]">
          {t(@locale, @locale_version, "Aktive Alarme")}
        </p>
        <span class="bac-badge bac-badge-sm bac-badge-error">{length(@entries)}</span>
      </div>

      <ul :if={@entries == []} class="bac-alarm-popup-empty">
        <li>{t(@locale, @locale_version, "Keine aktiven Alarme.")}</li>
      </ul>

      <ul :if={@entries != []} class="bac-alarm-popup-list" id="active-alarms-popup-list">
        <li :for={entry <- @entries} id={"active-alarm-entry-#{entry.id}"} class="bac-alarm-popup-item">
          <.link
            navigate={entry.object_path}
            class="bac-alarm-popup-link"
            title={t(@locale, @locale_version, "Objekteigenschaften öffnen")}
          >
            <div class="min-w-0 flex-1">
              <div class="flex items-baseline gap-2 min-w-0">
                <span :if={@show_device} class="bac-text-faint text-xs shrink-0 max-w-[7rem] truncate">
                  {entry.device_label || entry.device_id}
                </span>
                <span class="bac-mono text-sm text-[var(--bac-text)] truncate">
                  {entry.object_label}
                </span>
              </div>
              <p :if={entry.description} class="text-xs bac-text-muted mt-0.5 break-words">
                {entry.description}
              </p>
            </div>
            <div class="shrink-0 text-right min-w-[5.5rem]">
              <p class="text-xs bac-text-faint whitespace-nowrap">{entry.alarm_since_label}</p>
            </div>
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
