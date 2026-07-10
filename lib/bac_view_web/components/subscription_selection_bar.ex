defmodule BacViewWeb.SubscriptionSelectionBar do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:count, :integer, required: true)

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
          class="bac-btn bac-btn-primary bac-btn-sm"
        >
          <.icon name="hero-signal" class="size-4" />
          {t(@locale, @locale_version, "Erneut abonnieren")}
        </button>
        <button
          type="button"
          phx-click="unsubscribe_selected_subscriptions"
          class="bac-btn bac-btn-ghost bac-btn-sm text-[var(--bac-rose)]"
        >
          <.icon name="hero-signal-slash" class="size-4" />
          {t(@locale, @locale_version, "Ausgewählte kündigen")}
        </button>
        <button
          type="button"
          phx-click="clear_subscription_selection"
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          {t(@locale, @locale_version, "Auswahl aufheben")}
        </button>
      </div>
    </div>
    """
  end
end
