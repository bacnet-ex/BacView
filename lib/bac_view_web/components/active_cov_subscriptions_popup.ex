defmodule BacViewWeb.ActiveCovSubscriptionsPopup do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:count, :integer, required: true)
  attr(:open, :boolean, default: false)
  attr(:show_cov_label, :boolean, default: true)

  def active_cov_badge(assigns) do
    ~H"""
    <button
      :if={@count > 0}
      type="button"
      id="active-cov-badge"
      phx-click="toggle_cov_popup"
      class={[
        "bac-badge bac-badge-success cursor-pointer transition-all",
        "hover:ring-2 hover:ring-[var(--bac-emerald)]/40",
        @open && "ring-2 ring-[var(--bac-emerald)]/50"
      ]}
      aria-expanded={to_string(@open)}
      aria-haspopup="dialog"
    >
      <.icon name="hero-signal" class="size-3" />
      {@count}
      <span :if={@show_cov_label} class="normal-case tracking-normal">
        COV
      </span>
    </button>
    """
  end

  attr(:open, :boolean, default: false)
  attr(:entries, :list, default: [])
  attr(:grouped?, :boolean, default: false)
  attr(:device_groups, :list, default: [])
  attr(:total_count, :integer, default: 0)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def active_cov_panel(assigns) do
    assigns = assign(assigns, :header_count, panel_header_count(assigns))

    ~H"""
    <div
      :if={@open}
      id="active-cov-popup"
      phx-hook="FilterMenu"
      data-trigger-id="active-cov-badge"
      data-close-event="close_cov_popup"
      class="bac-alarm-popup bac-filter-menu--floating"
      role="dialog"
      aria-label={t(@locale, @locale_version, "Aktive COV-Abonnements")}
    >
      <div class="bac-alarm-popup-header">
        <p class="text-xs font-semibold text-[var(--bac-text)]">
          {t(@locale, @locale_version, "Aktive COV-Abonnements")}
        </p>
        <span class="bac-badge bac-badge-sm bac-badge-success">{@header_count}</span>
      </div>

      <.cov_device_groups_list
        :if={@grouped?}
        device_groups={@device_groups}
        locale={@locale}
        locale_version={@locale_version}
      />

      <ul :if={!@grouped? && @entries == []} class="bac-alarm-popup-empty">
        <li>{t(@locale, @locale_version, "Keine aktiven COV-Abonnements.")}</li>
      </ul>

      <ul :if={!@grouped? && @entries != []} class="bac-alarm-popup-list" id="active-cov-popup-list">
        <li
          :for={entry <- @entries}
          id={"active-cov-entry-#{entry.id}"}
          class="bac-alarm-popup-item"
        >
          <div class="flex items-stretch gap-1 min-w-0">
            <.link
              navigate={entry.object_path}
              class="bac-alarm-popup-link flex-1 min-w-0"
              title={t(@locale, @locale_version, "Objekteigenschaften öffnen")}
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-baseline gap-2 min-w-0">
                  <span class="bac-mono text-sm text-[var(--bac-text)] truncate">
                    {entry.object_label}
                  </span>
                  <span class="bac-mono text-xs bac-text-faint shrink-0">
                    {entry.property_label}
                  </span>
                </div>
                <p
                  :if={entry.object_name || entry.description}
                  class="text-xs bac-text-muted mt-0.5 break-words"
                >
                  {entry.object_name || entry.description}
                </p>
              </div>
              <div class="shrink-0 text-right min-w-[4.5rem]">
                <p class="bac-mono text-xs text-[var(--bac-emerald)] whitespace-nowrap">
                  {entry.value_label}
                </p>
              </div>
            </.link>
            <button
              :if={entry.chartable?}
              type="button"
              id={"cov-popup-chart-#{entry.id}"}
              phx-click="open_cov_chart_modal"
              phx-value-type={entry.type}
              phx-value-instance={entry.instance}
              phx-value-property={entry.property}
              class="bac-btn bac-btn-ghost bac-btn-xs shrink-0 self-center mx-1"
              title={t(@locale, @locale_version, "Diagramm")}
              aria-label={t(@locale, @locale_version, "Diagramm")}
            >
              <.icon name="hero-chart-bar" class="size-3.5" />
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr(:device_groups, :list, required: true)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp cov_device_groups_list(assigns) do
    ~H"""
    <ul :if={@device_groups == []} class="bac-alarm-popup-empty">
      <li>{t(@locale, @locale_version, "Keine aktiven COV-Abonnements.")}</li>
    </ul>

    <ul
      :if={@device_groups != []}
      class="bac-alarm-popup-list"
      id="active-cov-popup-device-list"
    >
      <li
        :for={group <- @device_groups}
        id={"active-cov-device-#{group.device_id}"}
        class="bac-alarm-popup-item"
      >
        <.link
          navigate={group.device_path}
          class="bac-alarm-popup-link"
          title={t(@locale, @locale_version, "%{count} COV aktiv", count: group.count)}
        >
          <span class="min-w-0 flex-1">
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
            <span class="bac-badge bac-badge-sm bac-badge-success">{group.count}</span>
            <.icon name="hero-chevron-right" class="size-4 bac-text-faint" />
          </span>
        </.link>
      </li>
    </ul>
    """
  end

  defp panel_header_count(%{grouped?: true, total_count: total_count}), do: total_count

  defp panel_header_count(%{entries: entries}), do: length(entries)
end
