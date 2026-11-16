defmodule BacViewWeb.SCCredentialsPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:uploads, :map, required: true)
  attr(:form, :map, required: true)
  attr(:summary, :map, default: nil)
  attr(:result, :atom, default: nil)
  attr(:stack_status, :map, required: true)

  def sc_credentials_panel(assigns) do
    ~H"""
    <.form
      for={@form}
      id="sc-credentials-form"
      phx-change="sc_credentials_change"
      phx-submit="sc_credentials_import"
      class="space-y-2 border-t border-[var(--bac-border)] pt-3"
    >
      <h3 class="text-sm font-semibold">
        {t(@locale, @locale_version, "BACnet/SC-Zertifikate")}
      </h3>
      <p :if={@summary} id="sc-certificate-expiry" class="text-xs bac-text-faint">
        {t(@locale, @locale_version, "Zertifikat gültig bis %{date}",
          date: BacView.Timezone.format(@summary.expires_at, "%d.%m.%Y %H:%M %Z")
        )}
      </p>
      <p
        :if={restart_required?(@summary, @stack_status)}
        id="sc-credentials-restart-required"
        class="text-xs bac-text-faint"
      >
        {t(@locale, @locale_version, "Stack neu starten, um die importierten Zertifikate zu verwenden.")}
      </p>
      <div :for={{upload, label} <- upload_fields(@uploads, @locale, @locale_version)}>
        <label class="bac-label" for={upload.ref}>{label}</label>
        <.live_file_input upload={upload} class="bac-input bac-input-sm w-full" />
        <p
          :for={error <- upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))}
          class="text-xs text-[var(--bac-rose)]"
        >
          {upload_error(error, @locale, @locale_version)}
        </p>
      </div>
      <p :if={@result == :imported} id="sc-credentials-imported" class="text-xs bac-text-faint">
        {t(@locale, @locale_version, "BACnet/SC-Zertifikate importiert.")}
      </p>
      <p :if={@result && @result != :imported} id="sc-credentials-error" class="text-xs text-[var(--bac-rose)]">
        {BacViewWeb.ErrorMessageText.format(@result, @locale, @locale_version)}
      </p>
      <button id="sc-credentials-import-btn" type="submit" class="bac-btn bac-btn-ghost bac-btn-sm w-full">
        {t(@locale, @locale_version, "PEM-Dateien importieren")}
      </button>
    </.form>
    """
  end

  defp upload_fields(uploads, locale, lv) do
    [
      {uploads.sc_certificate, t(locale, lv, "Betriebszertifikat (PEM)")},
      {uploads.sc_key, t(locale, lv, "Privater Schlüssel (PEM, unverschlüsselt)")},
      {uploads.sc_issuers, t(locale, lv, "Ausstellerzertifikate (1–2 PEM-Dateien)")}
    ]
  end

  defp restart_required?(%{id: id}, %{sc_credential_id: current}) when is_binary(current),
    do: id != current

  defp restart_required?(_summary, _status), do: false

  defp upload_error(:too_large, locale, lv),
    do: t(locale, lv, "PEM-Datei ist grösser als 64 KiB.")

  defp upload_error(:too_many_files, locale, lv), do: t(locale, lv, "Zu viele PEM-Dateien.")

  defp upload_error(_reason, locale, lv),
    do: t(locale, lv, "PEM-Datei konnte nicht geladen werden.")
end
