defmodule BacViewWeb.ResetPriorityModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:modal, :map, required: true)
  attr(:busy, :boolean, default: false)

  def modal(assigns) do
    ~H"""
    <div id="reset-priority-modal" class="bac-modal-backdrop" phx-hook="FocusFirstInput">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_reset_priority_modal"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal" role="dialog" aria-modal="true" aria-labelledby="reset-priority-title">
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "Priorität zurücksetzen")}
              </p>
              <h2 id="reset-priority-title" class="font-semibold text-base mt-0.5">
                <%= if @modal.mode == :choose do %>
                  {t(@locale, @locale_version, "Priorität wählen")}
                <% else %>
                  {t(@locale, @locale_version, "Priorität %{priority} zurücksetzen",
                    priority: @modal.priority
                  )}
                <% end %>
              </h2>
            </div>
            <button
              type="button"
              phx-click="close_reset_priority_modal"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <p class="text-sm text-[var(--bac-text)]">
            {t(
              @locale,
              @locale_version,
              "NULL an Present Value schreiben und Prioritäts-Slot freigeben für %{count} commandable Objekt(e).",
              count: @modal.commandable_count
            )}
          </p>

          <p :if={@modal.skipped_count > 0} class="text-xs bac-text-faint">
            {t(
              @locale,
              @locale_version,
              "%{count} ausgewählte Objekt(e) sind nicht commandable und werden übersprungen.",
              count: @modal.skipped_count
            )}
          </p>

          <.form
            for={%{}}
            as={:reset_priority}
            id="reset-priority-form"
            phx-submit="confirm_reset_selected_priority"
          >
            <div :if={@modal.mode == :choose} class="space-y-1.5 mb-4">
              <label for="reset-priority-select" class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Priorität")}
              </label>
              <select
                id="reset-priority-select"
                name="priority"
                data-autofocus
                class="bac-input bac-input-sm w-full"
              >
                <option :for={p <- 1..16} value={p} selected={p == @modal.priority}>
                  {p}
                </option>
              </select>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2 pt-2">
              <button
                type="button"
                phx-click="close_reset_priority_modal"
                disabled={@busy}
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                id="reset-priority-confirm"
                disabled={@busy || @modal.commandable_count == 0}
                class="bac-btn bac-btn-primary bac-btn-sm"
              >
                <.icon :if={@busy} name="hero-arrow-path" class="size-4 animate-spin" />
                {t(@locale, @locale_version, "Zurücksetzen")}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
