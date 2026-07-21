defmodule BacViewWeb.LogViewerModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:open, :boolean, default: false)
  attr(:entries, :list, default: [])
  attr(:level_filter, :string, default: "debug")
  attr(:log_path, :string, default: nil)

  def modal(assigns) do
    ~H"""
    <div :if={@open} id="app-log-viewer" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_log_viewer"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal bac-modal-lg" role="dialog" aria-modal="true" style="max-width: 56rem;">
        <div class="bac-modal-body space-y-3">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h2 class="font-semibold text-base">
                {t(@locale, @locale_version, "Protokolle")}
              </h2>
              <p :if={@log_path} class="text-xs bac-text-faint bac-mono mt-0.5 truncate" title={@log_path}>
                {@log_path}
              </p>
            </div>
            <button
              type="button"
              phx-click="close_log_viewer"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <label class="text-xs bac-text-faint" for="log-viewer-level">
              {t(@locale, @locale_version, "Stufe")}
            </label>
            <form phx-change="log_viewer_filter" class="inline">
              <select
                id="log-viewer-level"
                name="level"
                class="bac-input bac-input-sm"
              >
                <option :for={level <- ~w(debug info warning error)} value={level} selected={level == @level_filter}>
                  {level}
                </option>
              </select>
            </form>
            <button
              type="button"
              id="log-viewer-refresh"
              phx-click="log_viewer_refresh"
              class="bac-btn bac-btn-ghost bac-btn-sm"
            >
              <.icon name="hero-arrow-path" class="size-3.5" />
              {t(@locale, @locale_version, "Aktualisieren")}
            </button>
            <button
              type="button"
              id="log-viewer-clear"
              phx-click="log_viewer_clear"
              class="bac-btn bac-btn-ghost bac-btn-sm"
            >
              {t(@locale, @locale_version, "Leeren")}
            </button>
          </div>

          <div
            id="log-viewer-entries"
            class="bac-mono text-xs max-h-[50vh] overflow-auto rounded-lg border border-base-300/40 bg-base-200/20 p-2 space-y-1"
          >
            <p :if={@entries == []} class="bac-text-faint p-2">
              {t(@locale, @locale_version, "Keine Log-Einträge.")}
            </p>
            <div
              :for={entry <- @entries}
              id={"log-entry-#{entry.id}"}
              class={[
                "px-1 py-0.5 rounded",
                entry.level == :error && "text-error",
                entry.level == :warning && "text-[var(--bac-amber)]",
                entry.level == :info && "text-[var(--bac-text)]",
                entry.level == :debug && "bac-text-faint"
              ]}
            >
              <span class="bac-text-faint">
                {format_time(entry.time)}
              </span>
              <span class="uppercase ml-1">[{entry.level}]</span>
              <span class="ml-1 break-all">{entry.message}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_time(%DateTime{} = dt) do
    BacView.Timezone.format(dt, "%H:%M:%S")
  end

  defp format_time(_time), do: "--:--:--"
end
