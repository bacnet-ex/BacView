defmodule BacViewWeb.SubscriptionSelectionBar do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:count, :integer, required: true)
  attr(:disabled, :boolean, default: false)

  def selection_bar(assigns) do
    ~H"""
    <div
      id="subscription-selection-bar"
      class="flex flex-wrap items-center gap-2 px-4 py-2.5 mb-4 rounded-lg border border-[var(--bac-border)] bg-[var(--bac-surface)]"
    >
      <span class="text-sm font-medium text-[var(--bac-text)]">
        {t(@locale, @locale_version, "%{count} ausgewählt", count: @count)}
      </span>
      <div class="flex flex-wrap items-center gap-2 ml-auto">
        <button
          type="button"
          id="resubscribe-selected-subscriptions"
          phx-click="resubscribe_selected_subscriptions"
          disabled={@disabled}
          class="bac-btn bac-btn-primary bac-btn-sm"
        >
          <.icon name="hero-signal" class="size-4" />
          {t(@locale, @locale_version, "Erneut abonnieren")}
        </button>
        <button
          type="button"
          phx-click="unsubscribe_selected_subscriptions"
          disabled={@disabled}
          class="bac-btn bac-btn-ghost bac-btn-sm text-[var(--bac-rose)]"
        >
          <.icon name="hero-signal-slash" class="size-4" />
          {t(@locale, @locale_version, "Ausgewählte kündigen")}
        </button>
        <div class="bac-btn-split">
          <button
            type="button"
            id="export-selected-subscriptions-csv"
            phx-click="export_selected_subscriptions"
            phx-value-format="csv"
            disabled={@disabled}
            class="bac-btn bac-btn-ghost bac-btn-sm bac-btn-split-start"
            title={t(@locale, @locale_version, "COV-Meldungen der Auswahl als CSV exportieren")}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
            {t(@locale, @locale_version, "Als CSV exportieren")}
          </button>
          <details
            id="export-selected-subscriptions-menu"
            phx-hook="DetailsOutsideClose"
            class={[
              "bac-btn-split-details",
              @disabled && "pointer-events-none opacity-45"
            ]}
          >
            <summary
              class="bac-btn bac-btn-ghost bac-btn-sm bac-btn-split-end bac-btn-split-toggle"
              title={t(@locale, @locale_version, "Anderes Exportformat wählen")}
              aria-label={t(@locale, @locale_version, "Anderes Exportformat wählen")}
            >
              <.icon name="hero-chevron-down" class="size-3.5 opacity-70" />
            </summary>
            <div class="bac-btn-split-menu" role="menu">
              <button
                type="button"
                id="export-selected-subscriptions-json"
                role="menuitem"
                phx-click="export_selected_subscriptions"
                phx-value-format="json"
                disabled={@disabled}
                class="bac-btn-split-menu-item"
                title={t(@locale, @locale_version, "COV-Meldungen der Auswahl als JSON exportieren")}
              >
                {t(@locale, @locale_version, "Als JSON exportieren")}
              </button>
            </div>
          </details>
        </div>
        <button
          type="button"
          phx-click="clear_subscription_selection"
          disabled={@disabled}
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          {t(@locale, @locale_version, "Auswahl aufheben")}
        </button>
      </div>
    </div>
    """
  end
end
