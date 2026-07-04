defmodule BacViewWeb.DeviceLoadProgress do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:progress, :map, required: true)

  def load_progress(assigns) do
    assigns = assign(assigns, :progress, normalize_progress(assigns.progress))

    ~H"""
    <div id="device-load-progress" class="bac-panel mb-5">
      <div class="bac-panel-body space-y-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex items-center gap-3 min-w-0">
            <div class="bac-logo-mark shrink-0">
              <.icon name="hero-arrow-path" class="size-4 animate-spin" />
            </div>
            <div class="min-w-0">
              <p class="font-semibold text-sm text-[var(--bac-text)]">
                {stage_label(@progress.stage)}
              </p>
              <p :if={progress_detail(@progress)} class="text-xs bac-text-muted mt-0.5 truncate">
                {progress_detail(@progress)}
              </p>
            </div>
          </div>
          <span :if={progress_percent(@progress)} class="bac-badge bac-badge-accent shrink-0">
            {progress_percent(@progress)}%
          </span>
        </div>

        <div :if={@progress.total}>
          <progress class="bac-progress" value={@progress.done} max={max(@progress.total, 1)}>
          </progress>
          <div class="flex flex-wrap items-center justify-between gap-2 mt-2 text-xs bac-text-faint">
            <span>
              {t(@locale, @locale_version, "%{done} / %{total}", done: @progress.done, total: @progress.total)}
            </span>
            <span :if={@progress.errors > 0} class="text-[var(--bac-amber)]">
              {t(@locale, @locale_version, "%{count} Fehler", count: @progress.errors)}
            </span>
            <span :if={@progress.skipped > 0}>
              {t(@locale, @locale_version, "%{count} übersprungen", count: @progress.skipped)}
            </span>
          </div>
        </div>

        <p :if={is_nil(@progress.total) && @progress.stage != :building_hierarchy} class="text-xs bac-text-faint">
          {t(@locale, @locale_version, "Warte auf BACnet-Antwort…")}
        </p>
      </div>
    </div>
    """
  end

  defp normalize_progress(progress) when is_map(progress) do
    %{
      stage: Map.get(progress, :stage, :connecting),
      done: Map.get(progress, :done, 0),
      total: Map.get(progress, :total),
      errors: Map.get(progress, :errors, 0),
      skipped: Map.get(progress, :skipped, 0),
      detail: Map.get(progress, :detail)
    }
  end

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
end
