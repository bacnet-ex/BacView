defmodule BacViewWeb.BBMDPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:status, :map, required: true)
  attr(:form, :map, required: true)

  def bbmd_panel(assigns) do
    ~H"""
    <section id="bbmd-panel" class="bac-panel">
      <div class="bac-panel-header">
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-semibold">{t(@locale, @locale_version, "BBMD / Foreign Device")}</h2>
          <p class="text-xs bac-text-faint mt-0.5">{t(@locale, @locale_version, "Remote-Netzwerk-Zugang")}</p>
        </div>
        <span class={[
          "bac-badge bac-badge-sm shrink-0 max-w-[5.5rem] leading-tight",
          status_badge_class(@status.registration_status)
        ]}>
          {status_label(@status.registration_status, @locale, @locale_version)}
        </span>
      </div>

      <div class="bac-panel-body space-y-3">
        <p class="text-xs bac-text-muted leading-relaxed">
          {t(@locale, @locale_version, 
            "Registrieren Sie BacView als Foreign Device bei einem BBMD. Who-Is wird dann per Distribute-Broadcast-To-Network gesendet."
          )}
        </p>

        <.form for={@form} id="bbmd-form" phx-submit="bbmd_register" class="space-y-3">
          <div>
            <label class="bac-label" for={@form[:bbmd_host].id}>{t(@locale, @locale_version, "BBMD-Adresse")}</label>
            <.input
              field={@form[:bbmd_host]}
              type="text"
              placeholder="192.168.1.10"
              class="bac-input bac-input-sm"
            />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="bac-label" for={@form[:bbmd_port].id}>{t(@locale, @locale_version, "Port")}</label>
              <.input field={@form[:bbmd_port]} type="number" class="bac-input bac-input-sm" />
            </div>
            <div>
              <label class="bac-label" for={@form[:bbmd_ttl].id}>{t(@locale, @locale_version, "TTL (Sek.)")}</label>
              <.input field={@form[:bbmd_ttl]} type="number" class="bac-input bac-input-sm" />
            </div>
          </div>

          <div class="flex flex-wrap gap-2 pt-1">
            <button type="submit" class="bac-btn bac-btn-primary bac-btn-sm" id="bbmd-register-btn">
              {t(@locale, @locale_version, "Registrieren")}
            </button>
            <button
              type="button"
              phx-click="bbmd_unregister"
              disabled={@status.registration_status == :disabled}
              class="bac-btn bac-btn-ghost bac-btn-sm"
              id="bbmd-unregister-btn"
            >
              {t(@locale, @locale_version, "Abmelden")}
            </button>
          </div>
        </.form>

        <p :if={@status.registration_status == :registered} class="bac-mono text-xs bac-text-faint">
          {t(@locale, @locale_version, "Aktiv")}: {@status.bbmd_host}:{@status.bbmd_port}
          <span :if={@status.ttl}> · TTL {@status.ttl}s</span>
        </p>

        <p :if={@status.last_error} class="text-xs text-[var(--bac-rose)]">
          {inspect(@status.last_error)}
        </p>
      </div>
    </section>
    """
  end

  defp status_label(:registered, locale, lv), do: t(locale, lv, "Registriert")
  defp status_label(:waiting_for_ack, locale, lv), do: t(locale, lv, "Warte auf BBMD")
  defp status_label(:uninitialized, locale, lv), do: t(locale, lv, "Initialisiere")
  defp status_label(:disabled, locale, lv), do: t(locale, lv, "Inaktiv")
  defp status_label(_registered, locale, lv), do: t(locale, lv, "Unbekannt")

  defp status_badge_class(:registered), do: "bac-badge-success"
  defp status_badge_class(:waiting_for_ack), do: "bac-badge-warning"
  defp status_badge_class(:uninitialized), do: "bac-badge-warning"
  defp status_badge_class(_registered), do: "bac-badge-ghost"
end
