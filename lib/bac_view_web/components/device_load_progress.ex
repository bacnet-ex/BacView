defmodule BacViewWeb.DeviceLoadProgress do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:progress, :map, default: nil)

  def status_banner(assigns) do
    progress = normalize_progress(assigns.progress)

    assigns =
      assigns
      |> assign(:progress, progress)
      |> assign(:heading, stage_label(progress.stage))
      |> assign(:subtext, status_subtext(progress))

    ~H"""
    <div
      id="device-refresh-banner"
      role="status"
      aria-live="polite"
      class="mx-5 mt-3 rounded-lg border border-[var(--bac-accent)]/25 bg-[var(--bac-accent)]/8 px-4 py-3"
    >
      <div class="flex items-center gap-3 min-w-0">
        <.icon
          name="hero-arrow-path"
          class="size-4 shrink-0 animate-spin text-[var(--bac-accent)]"
        />
        <p class="text-sm font-medium text-[var(--bac-text)] truncate">{@heading}</p>
        <span :if={progress_percent(@progress)} class="bac-badge bac-badge-accent bac-badge-sm ml-auto shrink-0">
          {progress_percent(@progress)}%
        </span>
      </div>
      <p :if={@subtext} class="text-xs bac-text-muted mt-1.5 ml-7">{@subtext}</p>
      <div :if={@progress.total} class="mt-3 ml-7 space-y-1.5">
        <progress class="bac-progress" value={@progress.done} max={max(@progress.total, 1)} />
        <div class="flex flex-wrap items-center justify-between gap-2 text-xs bac-text-faint">
          <span>
            {t(@locale, @locale_version, "%{done} / %{total}", done: @progress.done, total: @progress.total)}
          </span>
          <span :if={@progress.skipped > 0}>
            {t(@locale, @locale_version, "%{count} übersprungen", count: @progress.skipped)}
          </span>
        </div>
      </div>

      <details
        :if={@progress.errors > 0}
        id="device-scan-error-log"
        class="bac-collapsible mt-3 ml-7"
      >
        <summary class="bac-collapsible-summary text-xs text-[var(--bac-amber)]">
          <.icon name="hero-chevron-right" class="bac-collapsible-icon size-3.5 shrink-0" />
          <span>
            {t(@locale, @locale_version, "Fehlerprotokoll (%{count})", count: @progress.errors)}
          </span>
        </summary>
        <ul class="bac-collapsible-content space-y-1.5 text-xs">
          <li
            :for={{entry, index} <- Enum.with_index(@progress.error_log, 1)}
            id={"device-scan-error-#{index}"}
            class="min-w-0"
          >
            <span :if={entry.object} class="bac-mono text-[var(--bac-text)]">
              {entry.object}
            </span>
            <span :if={entry.object} class="bac-text-faint mx-1">·</span>
            <span class="text-[var(--bac-amber)]">{entry.message}</span>
          </li>
        </ul>
      </details>
    </div>
    """
  end

  defp normalize_progress(nil),
    do: %{
      stage: :connecting,
      done: 0,
      total: nil,
      errors: 0,
      skipped: 0,
      detail: nil,
      error_log: []
    }

  defp normalize_progress(progress) when is_map(progress) do
    %{
      stage: Map.get(progress, :stage, :connecting),
      done: Map.get(progress, :done, 0),
      total: Map.get(progress, :total),
      errors: Map.get(progress, :errors, 0),
      skipped: Map.get(progress, :skipped, 0),
      detail: Map.get(progress, :detail),
      error_log: normalize_error_log(Map.get(progress, :error_log, []))
    }
  end

  defp normalize_error_log(error_log) when is_list(error_log) do
    Enum.map(error_log, fn
      %{object: object, message: message} when is_binary(message) ->
        %{object: object, message: message}

      %{object: object, message: message} ->
        %{object: object, message: to_string(message)}

      {object, message} ->
        %{object: object, message: to_string(message)}

      message when is_binary(message) ->
        %{object: nil, message: message}

      other ->
        %{object: nil, message: inspect(other)}
    end)
  end

  defp normalize_error_log(_error_log), do: []

  defp stage_label(:connecting),
    do: dgettext(BacViewWeb.Gettext, "default", "Verbindung zum Gerät…")

  defp stage_label(:reading_device),
    do: dgettext(BacViewWeb.Gettext, "default", "Geräteobjekt lesen…")

  defp stage_label(:reading_object_list),
    do: dgettext(BacViewWeb.Gettext, "default", "Objektliste abrufen…")

  defp stage_label(:scanning_objects),
    do: dgettext(BacViewWeb.Gettext, "default", "BACnet-Objekte scannen…")

  defp stage_label(:building_hierarchy),
    do: dgettext(BacViewWeb.Gettext, "default", "Hierarchie aufbauen…")

  defp stage_label(_connecting),
    do: dgettext(BacViewWeb.Gettext, "default", "Gerät wird geladen…")

  defp progress_percent(%{total: total, done: done})
       when is_integer(total) and total > 0 and is_integer(done) do
    min(100, trunc(done / total * 100))
  end

  defp progress_percent(_progress_percent), do: nil

  defp progress_detail(%{stage: :reading_object_list, done: done, total: total})
       when is_integer(done) and done > 0 and is_integer(total) and total > 0 do
    dgettext(BacViewWeb.Gettext, "default", "Objekt-IDs lesen: %{done} / %{total}", %{
      done: done,
      total: total
    })
  end

  defp progress_detail(%{stage: :reading_object_list, total: total})
       when is_integer(total) and total > 0 do
    dgettext(BacViewWeb.Gettext, "default", "%{count} Objekte in der Geräteliste gefunden", %{
      count: total
    })
  end

  defp progress_detail(%{stage: :scanning_objects, detail: detail}) when is_binary(detail) do
    dgettext(BacViewWeb.Gettext, "default", "Aktuell: %{object}", %{object: detail})
  end

  defp progress_detail(%{stage: :building_hierarchy, total: total})
       when is_integer(total) and total > 0 do
    dgettext(BacViewWeb.Gettext, "default", "%{count} Objekte verarbeiten", %{count: total})
  end

  defp progress_detail(_detail), do: nil

  defp status_subtext(progress) do
    case progress_detail(progress) do
      nil -> waiting_subtext(progress)
      detail -> detail
    end
  end

  defp waiting_subtext(%{stage: :building_hierarchy}), do: nil

  defp waiting_subtext(_progress) do
    dgettext(BacViewWeb.Gettext, "default", "Warte auf BACnet-Antwort…")
  end
end
