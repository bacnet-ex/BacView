defmodule BacViewWeb.BulkWritePropertyModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:modal, :map, required: true)

  def modal(assigns) do
    rows = assigns.modal.rows
    ok_count = Enum.count(rows, &(&1.status == :ok))
    failed_count = Enum.count(rows, &(&1.status == :error))
    finished = ok_count + failed_count

    assigns =
      assigns
      |> assign(:ok_count, ok_count)
      |> assign(:failed_count, failed_count)
      |> assign(:finished, finished)
      |> assign(:total, length(rows))

    ~H"""
    <div id="bulk-write-property-modal" class="bac-modal-backdrop" phx-hook="FocusFirstInput">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_bulk_write_property"
        disabled={@modal.busy}
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div
        class="bac-modal bac-modal-lg bac-modal-constrain"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bulk-write-property-title"
      >
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "Mehrauswahl")}
              </p>
              <h2 id="bulk-write-property-title" class="font-semibold text-base mt-0.5">
                {t(@locale, @locale_version, "Eigenschaft schreiben")}
              </h2>
              <p class="text-sm bac-text-faint mt-1">
                {t(@locale, @locale_version, "%{count} Objekte", count: @total)}
              </p>
            </div>
            <button
              type="button"
              id="bulk-write-close"
              phx-click="close_bulk_write_property"
              disabled={@modal.busy}
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <p
            :if={@modal.properties == []}
            id="bulk-write-no-properties"
            class="text-sm text-[var(--bac-text)]"
          >
            {t(
              @locale,
              @locale_version,
              "Die Auswahl hat keine gemeinsame schreibbare Eigenschaft."
            )}
          </p>

          <.form
            :if={@modal.properties != []}
            for={%{}}
            as={:bulk_write}
            id="bulk-write-property-form"
            phx-change="change_bulk_write_property"
            phx-submit="submit_bulk_write_property"
            class="space-y-4"
          >
            <p id="bulk-write-hint" class="text-xs bac-text-faint">
              {t(
                @locale,
                @locale_version,
                "Gemeinsame Eigenschaften der ausgewählten Objekttypen."
              )}
            </p>

            <div class="space-y-1.5">
              <label for="bulk-write-property" class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Eigenschaft")}
              </label>
              <select
                id="bulk-write-property"
                name="bulk_write[property]"
                data-autofocus
                disabled={@modal.busy}
                class="bac-input bac-input-sm w-full"
              >
                <option
                  :for={property <- @modal.properties}
                  value={property.id}
                  selected={property.id == @modal.property}
                >
                  {property.label}
                </option>
              </select>
            </div>

            <div class="space-y-1.5">
              <label for="bulk-write-value" class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Neuer Wert")}
              </label>
              <input
                type="text"
                id="bulk-write-value"
                name="bulk_write[value]"
                value={@modal.value}
                disabled={@modal.busy}
                autocomplete="off"
                spellcheck="false"
                class="bac-input bac-input-sm w-full"
              />
              <p :if={@modal.property == :present_value} class="text-xs bac-text-faint">
                {t(
                  @locale,
                  @locale_version,
                  "Für Present Value setzt null den Prioritäts-Slot zurück."
                )}
              </p>
            </div>

            <div :if={@modal.property == :present_value} class="space-y-1.5">
              <label for="bulk-write-priority" class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Priorität")}
              </label>
              <select
                id="bulk-write-priority"
                name="bulk_write[priority]"
                disabled={@modal.busy}
                class="bac-input bac-input-sm w-full"
              >
                <option :for={priority <- 1..16} value={priority} selected={priority == @modal.priority}>
                  {priority}
                </option>
              </select>
              <p class="text-xs bac-text-faint">
                {t(
                  @locale,
                  @locale_version,
                  "Wird bei commandable Objekten mitgeschrieben."
                )}
              </p>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2">
              <button
                type="button"
                id="bulk-write-cancel"
                phx-click="close_bulk_write_property"
                disabled={@modal.busy}
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                id="bulk-write-submit"
                disabled={@modal.busy}
                class="bac-btn bac-btn-primary bac-btn-sm"
              >
                <.icon :if={@modal.busy} name="hero-arrow-path" class="size-4 animate-spin" />
                {t(@locale, @locale_version, "Schreiben")}
              </button>
            </div>
          </.form>

          <p :if={@modal.busy} id="bulk-write-progress" class="text-sm text-[var(--bac-text)]">
            {t(@locale, @locale_version, "%{done} / %{total}", done: @finished, total: @total)}
          </p>
          <p
            :if={!@modal.busy and @finished > 0}
            id="bulk-write-summary"
            class="text-sm text-[var(--bac-text)]"
          >
            {t(
              @locale,
              @locale_version,
              "%{ok} geschrieben, %{failed} fehlgeschlagen.",
              ok: @ok_count,
              failed: @failed_count
            )}
          </p>

          <div class="bac-table-wrap max-h-72 overflow-auto">
            <table id="bulk-write-results" class="bac-table w-full text-sm">
              <thead>
                <tr>
                  <th>{t(@locale, @locale_version, "Objekt")}</th>
                  <th>{t(@locale, @locale_version, "Status")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @modal.rows} id={"bulk-write-row-#{row.type}-#{row.instance}"}>
                  <td class="min-w-0">
                    <div class="font-medium break-words">{row.name}</div>
                    <div class="text-xs bac-text-faint">
                      {row.type_label} {row.instance}
                    </div>
                  </td>
                  <td
                    id={"bulk-write-status-#{row.type}-#{row.instance}"}
                    data-status={row.status}
                    class="align-top"
                  >
                    <%= cond do %>
                      <% row.status == :writing -> %>
                        <span class="inline-flex items-center gap-1.5">
                          <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                          {t(@locale, @locale_version, "Schreiben…")}
                        </span>
                      <% row.status == :queued -> %>
                        <span class="bac-text-faint">{t(@locale, @locale_version, "Wartet")}</span>
                      <% row.status == :ok -> %>
                        <span class="bac-badge bac-badge-sm bac-badge-success">
                          {t(@locale, @locale_version, "Geschrieben")}
                        </span>
                      <% row.status == :error -> %>
                        <div class="space-y-1">
                          <span class="bac-badge bac-badge-sm bac-badge-error">
                            {t(@locale, @locale_version, "Fehler")}
                          </span>
                          <p class="text-xs break-words">{row.message}</p>
                        </div>
                      <% true -> %>
                        <span class="bac-text-faint">{t(@locale, @locale_version, "Bereit")}</span>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
