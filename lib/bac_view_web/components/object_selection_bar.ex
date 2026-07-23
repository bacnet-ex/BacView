defmodule BacViewWeb.ObjectSelectionBar do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:count, :integer, required: true)
  attr(:write_priority, :integer, default: 8)
  attr(:bulk_resetting, :boolean, default: false)

  def selection_bar(assigns) do
    ~H"""
    <div
      id="object-selection-bar"
      class="flex flex-wrap items-center gap-2 px-4 py-2.5 mb-4 rounded-lg border border-[var(--bac-border)] bg-[var(--bac-surface)]"
    >
      <span class="text-sm font-medium text-[var(--bac-text)]">
        {t(@locale, @locale_version, "%{count} ausgewählt", count: @count)}
      </span>
      <div class="flex flex-wrap items-center gap-2 ml-auto">
        <button
          type="button"
          phx-click="subscribe_selected_cov"
          disabled={@bulk_resetting}
          class="bac-btn bac-btn-primary bac-btn-sm"
        >
          <.icon name="hero-signal" class="size-4" />
          {t(@locale, @locale_version, "COV abonnieren")}
        </button>
        <button
          type="button"
          phx-click="unsubscribe_selected_cov"
          disabled={@bulk_resetting}
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          {t(@locale, @locale_version, "COV kündigen")}
        </button>
        <div class="flex flex-wrap items-center gap-1.5">
          <button
            type="button"
            id="reset-selected-priority"
            phx-click="open_reset_priority_confirm"
            disabled={@bulk_resetting}
            class="bac-btn bac-btn-ghost bac-btn-sm"
            title={
              t(
                @locale,
                @locale_version,
                "Priorität %{priority} bei ausgewählten commandable Objekten zurücksetzen (NULL)",
                priority: @write_priority
              )
            }
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" />
            {t(@locale, @locale_version, "Priorität %{priority} zurücksetzen",
              priority: @write_priority
            )}
          </button>
          <button
            type="button"
            id="reset-selected-priority-other"
            phx-click="open_reset_priority_choose"
            disabled={@bulk_resetting}
            class="bac-btn bac-btn-ghost bac-btn-sm"
            title={t(@locale, @locale_version, "Andere Priorität wählen und zurücksetzen")}
          >
            {t(@locale, @locale_version, "Andere Priorität…")}
          </button>
        </div>
        <button
          type="button"
          phx-click="clear_selection"
          disabled={@bulk_resetting}
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          {t(@locale, @locale_version, "Auswahl aufheben")}
        </button>
      </div>
    </div>
    """
  end
end
