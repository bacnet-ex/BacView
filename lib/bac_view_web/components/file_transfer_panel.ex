defmodule BacViewWeb.FileTransferPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:metadata, :map, required: true)
  attr(:content, :map, default: nil)
  attr(:busy, :boolean, default: false)
  attr(:uploads, :map, default: %{})

  def panel(assigns) do
    ~H"""
    <section id="file-transfer-panel" class="bac-panel">
      <div class="bac-panel-header flex-wrap gap-3">
        <div class="min-w-0">
          <p class="bac-section-title">{t(@locale, @locale_version, "Dateiübertragung")}</p>
          <p class="text-xs bac-text-faint mt-0.5">
            {access_label(@metadata.stream_access, @locale, @locale_version)}
            <span :if={@metadata.file_size}>
              · {t(@locale, @locale_version, "%{size} Bytes", size: @metadata.file_size)}
            </span>
            <span :if={@metadata.read_only}>
              · {t(@locale, @locale_version, "Schreibgeschützt")}
            </span>
          </p>
        </div>
        <div class="flex items-center gap-2 ml-auto">
          <button
            type="button"
            id="download-file-btn"
            phx-click="download_file_content"
            disabled={@busy || is_nil(@content)}
            class="bac-btn bac-btn-ghost bac-btn-sm"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
            {t(@locale, @locale_version, "Herunterladen")}
          </button>
          <button
            type="button"
            id="read-file-btn"
            phx-click="read_file"
            disabled={@busy}
            class="bac-btn bac-btn-primary bac-btn-sm"
          >
            <%= if @busy do %>
              <.icon name="hero-arrow-path" class="size-4 animate-spin" />
            <% end %>
            {t(@locale, @locale_version, "Datei lesen")}
          </button>
        </div>
      </div>

      <div :if={@content} id="file-content-preview" class="border-t border-[var(--bac-border)]">
        <div class="px-5 py-3 flex flex-wrap items-center justify-between gap-2 border-b border-[var(--bac-border)] bg-[var(--bac-bg-elevated)]">
          <p class="text-xs bac-text-faint">
            {t(@locale, @locale_version, "Gelesen: %{size} Bytes", size: @content.size)}
            <span :if={@content.truncated}>
              · {t(@locale, @locale_version, "Vorschau gekürzt")}
            </span>
          </p>
          <span class={[
            "bac-badge bac-badge-xs",
            @content.printable && "bac-badge-success" || "bac-badge-ghost"
          ]}>
            <%= if @content.printable do %>
              {t(@locale, @locale_version, "Text")}
            <% else %>
              {t(@locale, @locale_version, "Binär")}
            <% end %>
          </span>
        </div>

        <%= if @content.printable do %>
          <pre id="file-content-text" phx-no-curly-interpolation class="bac-file-preview"><%= @content.preview %></pre>
        <% else %>
          <div id="file-content-binary" class="bac-file-preview-empty">
            <.icon name="hero-document" class="size-8 opacity-40" />
            <p class="text-sm text-[var(--bac-text-muted)]">
              {t(@locale, @locale_version, "Binärdatei - Inhalt kann nicht als Text angezeigt werden.")}
            </p>
            <p class="text-xs bac-text-faint">
              {t(@locale, @locale_version, "Verwenden Sie „Herunterladen“, um die Datei zu speichern.")}
            </p>
          </div>
        <% end %>
      </div>

      <div :if={!@metadata.read_only} class="p-5 border-t border-[var(--bac-border)] space-y-3">
        <p class="text-sm text-[var(--bac-text-muted)]">
          {t(@locale, @locale_version, "Datei auf das Gerät schreiben (Atomic Write File).")}
        </p>
        <.form
          for={%{}}
          id="write-file-form"
          phx-submit="write_file"
          phx-change="validate_file_upload"
        >
          <div class="flex flex-wrap items-center gap-3">
            <.live_file_input
              :if={Map.has_key?(@uploads, :bac_file_upload)}
              upload={@uploads.bac_file_upload}
              class="bac-input bac-input-sm max-w-md"
            />
            <button
              type="submit"
              id="write-file-btn"
              disabled={@busy || !upload_ready?(@uploads)}
              class="bac-btn bac-btn-ghost bac-btn-sm"
            >
              {t(@locale, @locale_version, "Datei schreiben")}
            </button>
          </div>
        </.form>
      </div>
    </section>
    """
  end

  defp access_label(true, locale, v),
    do: BacViewWeb.GettextLC.t(locale, v, "Stream-Zugriff")

  defp access_label(false, locale, v),
    do: BacViewWeb.GettextLC.t(locale, v, "Datensatz-Zugriff")

  defp upload_ready?(uploads) do
    case Map.get(uploads, :bac_file_upload) do
      %{entries: [entry | _uploads]} -> entry.done?
      _uploads -> false
    end
  end
end
