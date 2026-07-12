defmodule BacViewWeb.CovNotificationChartModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.Timezone

  attr(:subscription, :map, required: true)
  attr(:object, :map, default: nil)
  attr(:loading, :boolean, default: false)
  attr(:error, :string, default: nil)
  attr(:start_value, :string, default: "")
  attr(:end_value, :string, default: "")
  attr(:has_data, :boolean, default: false)
  attr(:record_count, :integer, default: 0)

  def modal(assigns) do
    ~H"""
    <div id="cov-notification-chart-modal" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_cov_chart_modal"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal bac-modal-chart" role="dialog" aria-modal="true">
        <div class="bac-modal-body space-y-4 min-h-0">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "COV-Verlauf")}
              </p>
              <h2 class="font-semibold text-base truncate mt-0.5">
                {chart_title(@object, @subscription)}
              </h2>
              <p :if={object_description(@object)} class="text-sm bac-text-muted truncate mt-0.5">
                {object_description(@object)}
              </p>
              <p class="bac-mono text-xs bac-text-faint mt-0.5">
                {@subscription.object_id.type}:{@subscription.object_id.instance} · {@subscription.property}
                · {t(@locale, @locale_version, "Aus empfangenen COV-Meldungen")}
              </p>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <button
                type="button"
                id="cov-chart-export-csv"
                phx-click="cov_chart_export_csv"
                disabled={@loading || not @has_data}
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />
                {t(@locale, @locale_version, "CSV")}
              </button>
              <button
                type="button"
                id="cov-chart-export-json"
                phx-click="cov_chart_export_json"
                disabled={@loading || not @has_data}
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />
                {t(@locale, @locale_version, "JSON")}
              </button>
              <button
                type="button"
                phx-click="close_cov_chart_modal"
                class="bac-btn bac-btn-ghost bac-btn-icon"
                aria-label={t(@locale, @locale_version, "Schliessen")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>

          <form
            id="cov-chart-range-form"
            phx-change="cov_chart_change_range"
            phx-submit="cov_chart_load"
            class="flex flex-wrap items-end gap-3"
          >
            <div class="min-w-[12rem] flex-1">
              <label for="cov-chart-start" class="block text-xs bac-text-faint mb-1">
                {t(@locale, @locale_version, "Von")}
              </label>
              <input
                id="cov-chart-start"
                name="start"
                type="datetime-local"
                value={@start_value}
                class="bac-input w-full"
              />
            </div>
            <div class="min-w-[12rem] flex-1">
              <label for="cov-chart-end" class="block text-xs bac-text-faint mb-1">
                {t(@locale, @locale_version, "Bis")}
              </label>
              <input
                id="cov-chart-end"
                name="end"
                type="datetime-local"
                value={@end_value}
                class="bac-input w-full"
              />
            </div>
            <button
              type="submit"
              id="cov-chart-load"
              disabled={@loading}
              class="bac-btn bac-btn-primary bac-btn-sm"
            >
              <.icon :if={@loading} name="hero-arrow-path" class="size-4 animate-spin" />
              {t(@locale, @locale_version, "Laden")}
            </button>
          </form>

          <p :if={@error} class="text-sm text-[var(--bac-rose)]" id="cov-chart-error">
            {@error}
          </p>

          <p :if={@has_data && !@loading} class="text-xs bac-text-faint" id="cov-chart-meta">
            {t(@locale, @locale_version, "%{count} Datensätze", count: @record_count)}
          </p>

          <div
            id="cov-notification-chart-hook"
            phx-hook="TrendLogChart"
            phx-update="ignore"
            data-locale="de-DE"
            data-timezone={Timezone.name()}
            class="bac-trend-chart-shell flex-1 min-h-0"
          >
            <div data-chart-empty class="hidden text-sm bac-text-muted py-10 text-center"></div>
            <div data-chart-canvas class="w-full flex-1 min-h-0"></div>
            <div data-chart-tooltip class="bac-trend-chart-tooltip hidden" role="tooltip"></div>
            <div data-chart-legend class="bac-trend-legend mt-3"></div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp chart_title(object, %{object_id: %{type: type, instance: instance}}) do
    case object do
      %{name: name} when is_binary(name) ->
        case String.trim(name) do
          "" -> "#{type}:#{instance}"
          trimmed -> trimmed
        end

      _object ->
        "#{type}:#{instance}"
    end
  end

  defp object_description(%{description: description}) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_description(_object), do: nil
end
