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
  attr(:grouped?, :boolean, default: false)
  attr(:level, :atom, default: :entries, values: [:devices, :entries])
  attr(:device_groups, :list, default: [])
  attr(:selected_device_id, :integer, default: nil)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def active_alarms_panel(assigns) do
    assigns =
      assign(
        assigns,
        :header_title,
        panel_header_title(
          assigns.grouped?,
          assigns.level,
          assigns.device_groups,
          assigns.selected_device_id,
          assigns.locale,
          assigns.locale_version
        )
      )

    assigns = assign(assigns, :header_count, panel_header_count(assigns))

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
        <div class="flex items-center gap-2 min-w-0">
          <button
            :if={@grouped? && @level == :entries}
            type="button"
            id="active-alarms-popup-back"
            phx-click="back_alarm_popup_devices"
            class="bac-btn bac-btn-ghost bac-btn-icon bac-btn-xs shrink-0"
            aria-label={t(@locale, @locale_version, "Zurück")}
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </button>
          <p class="text-xs font-semibold text-[var(--bac-text)] truncate">
            {@header_title}
          </p>
        </div>
        <span class="bac-badge bac-badge-sm bac-badge-error">{@header_count}</span>
      </div>

      <.device_groups_list
        :if={@grouped? && @level == :devices}
        device_groups={@device_groups}
        locale={@locale}
        locale_version={@locale_version}
      />

      <.alarm_entries_list
        :if={!@grouped? || @level == :entries}
        entries={@entries}
        show_device={@show_device}
        locale={@locale}
        locale_version={@locale_version}
      />
    </div>
    """
  end

  attr(:device_groups, :list, required: true)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp device_groups_list(assigns) do
    ~H"""
    <ul :if={@device_groups == []} class="bac-alarm-popup-empty">
      <li>{t(@locale, @locale_version, "Keine aktiven Alarme.")}</li>
    </ul>

    <ul
      :if={@device_groups != []}
      class="bac-alarm-popup-list"
      id="active-alarms-popup-device-list"
    >
      <li
        :for={group <- @device_groups}
        id={"active-alarm-device-#{group.device_id}"}
        class="bac-alarm-popup-item"
      >
        <button
          type="button"
          phx-click="select_alarm_popup_device"
          phx-value-device_id={group.device_id}
          class="bac-alarm-popup-device-btn"
          title={t(@locale, @locale_version, "%{count} aktive Alarme", count: group.count)}
        >
          <span class="min-w-0 flex-1 text-left">
            <span class="text-sm text-[var(--bac-text)] truncate block">
              {group.device_label}
            </span>
            <span
              :if={group.device_description}
              class="text-xs bac-text-muted truncate block mt-0.5"
            >
              {group.device_description}
            </span>
          </span>
          <span class="flex items-center gap-1.5 shrink-0">
            <span class="bac-badge bac-badge-sm bac-badge-error">{group.count}</span>
            <.icon name="hero-chevron-right" class="size-4 bac-text-faint" />
          </span>
        </button>
      </li>
    </ul>
    """
  end

  attr(:entries, :list, required: true)
  attr(:show_device, :boolean, default: true)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp alarm_entries_list(assigns) do
    ~H"""
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
    """
  end

  defp panel_header_title(false, _level, _groups, _device_id, locale, locale_version) do
    t(locale, locale_version, "Aktive Alarme")
  end

  defp panel_header_title(true, :devices, _groups, _device_id, locale, locale_version) do
    t(locale, locale_version, "Aktive Alarme")
  end

  defp panel_header_title(true, :entries, groups, device_id, _locale, _locale_version) do
    groups
    |> Enum.find(fn group -> group.device_id == device_id end)
    |> case do
      %{device_label: label} -> label
      _group -> Integer.to_string(device_id)
    end
  end

  defp panel_header_count(%{grouped?: true, level: :devices, device_groups: groups}) do
    groups
    |> Enum.map(& &1.count)
    |> Enum.sum()
  end

  defp panel_header_count(%{grouped?: true, level: :entries, entries: entries}) do
    length(entries)
  end

  defp panel_header_count(%{entries: entries}) do
    length(entries)
  end
end
