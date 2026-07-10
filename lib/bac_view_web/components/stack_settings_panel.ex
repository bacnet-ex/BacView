defmodule BacViewWeb.StackSettingsPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.TransportResolver

  attr(:form, :map, required: true)
  attr(:settings, :map, required: true)
  attr(:stack_status, :map, required: true)
  attr(:interface_options, :list, required: true)
  attr(:confirm_restart?, :boolean, default: false)
  attr(:apply_disabled?, :boolean, default: false)

  def stack_settings_panel(assigns) do
    ~H"""
    <section id="stack-settings-panel" class="bac-panel">
      <div class="bac-panel-header">
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-semibold">{t(@locale, @locale_version, "Stack-Einstellungen")}</h2>
          <p class="text-xs bac-text-faint mt-0.5">
            {t(@locale, @locale_version, "Transport & lokales Gerät")}
          </p>
        </div>
        <div class="flex flex-col items-end gap-1 shrink-0">
          <span
            id="stack-status-badge"
            class={[
              "bac-badge bac-badge-sm",
              stack_status_badge_class(@stack_status)
            ]}
          >
            {stack_status_label(@stack_status, @locale, @locale_version)}
          </span>
          <span class="bac-badge bac-badge-sm bac-badge-ghost">
            {transport_label(@settings.transport, @locale, @locale_version)}
          </span>
        </div>
      </div>

      <div class="bac-panel-body space-y-3">
        <p
          :if={stack_error_message(@stack_status)}
          id="stack-status-error"
          class="text-xs text-[var(--bac-rose)]"
        >
          {stack_error_message(@stack_status)}
        </p>

        <p :if={@settings.interface_error} class="text-xs text-[var(--bac-rose)]">
          {interface_error_label(@settings.interface_error, @locale, @locale_version)}
        </p>

        <.form
          for={@form}
          id="stack-settings-form"
          phx-change="stack_settings_change"
          phx-submit="stack_settings_save"
          class="space-y-3"
        >
          <div>
            <label class="bac-label" for={@form[:transport].id}>
              {t(@locale, @locale_version, "Transport")}
            </label>
            <.input
              field={@form[:transport]}
              type="select"
              options={transport_options(@locale, @locale_version)}
              class="bac-input bac-input-sm"
            />
          </div>

          <div>
            <div class="flex items-center justify-between gap-2">
              <label class="bac-label mb-0" for={@form[:interface].id}>
                {interface_label(@form[:transport].value, @locale, @locale_version)}
              </label>
              <button
                type="button"
                phx-click="stack_settings_refresh_interfaces"
                class="bac-btn bac-btn-ghost bac-btn-sm shrink-0 px-2"
                id="stack-settings-refresh-interfaces-btn"
                title={t(@locale, @locale_version, "Schnittstellen aktualisieren")}
                aria-label={t(@locale, @locale_version, "Schnittstellen aktualisieren")}
              >
                <.icon name="hero-arrow-path" class="w-4 h-4" />
              </button>
            </div>
            <.input
              field={@form[:interface]}
              type="select"
              options={interface_select_options(@interface_options)}
              class="bac-input bac-input-sm mt-1"
              disabled={@interface_options == []}
            />
          </div>

          <div :if={mstp_transport?(@form[:transport].value)} class="grid grid-cols-2 gap-2">
            <div>
              <label class="bac-label" for={@form[:mstp_local_address].id}>
                {t(@locale, @locale_version, "MS/TP-Adresse")}
              </label>
              <.input
                field={@form[:mstp_local_address]}
                type="number"
                min="0"
                max="127"
                class="bac-input bac-input-sm"
              />
            </div>
            <div>
              <label class="bac-label" for={@form[:mstp_baud_rate].id}>
                {t(@locale, @locale_version, "Baudrate")}
              </label>
              <.input
                field={@form[:mstp_baud_rate]}
                type="select"
                options={baud_rate_options(@locale, @locale_version)}
                class="bac-input bac-input-sm"
              />
            </div>
          </div>

          <div>
            <label class="bac-label" for={@form[:device_id].id}>
              {t(@locale, @locale_version, "Geräte-Instanz")}
            </label>
            <.input
              field={@form[:device_id]}
              type="number"
              min="0"
              max="4194303"
              class="bac-input bac-input-sm"
            />
          </div>

          <div>
            <label class="bac-label" for={@form[:cov_lifetime_seconds].id}>
              {t(@locale, @locale_version, "COV-Lifetime (Sek.)")}
            </label>
            <.input
              field={@form[:cov_lifetime_seconds]}
              type="number"
              min="0"
              class="bac-input bac-input-sm"
            />
          </div>

          <div>
            <label class="bac-label" for={@form[:cov_increment].id}>
              {t(@locale, @locale_version, "COV-Inkrement")}
            </label>
            <.input
              field={@form[:cov_increment]}
              type="number"
              min="0"
              step="any"
              placeholder={t(@locale, @locale_version, "Leer = Objektstandard")}
              class="bac-input bac-input-sm"
            />
          </div>

          <div>
            <label
              for={@form[:cov_confirmed].id}
              class="flex items-center gap-2 text-xs bac-text-muted cursor-pointer min-h-9"
            >
              <input type="hidden" name={@form[:cov_confirmed].name} value="false" />
              <input
                type="checkbox"
                id={@form[:cov_confirmed].id}
                name={@form[:cov_confirmed].name}
                value="true"
                checked={@form[:cov_confirmed].value in [true, "true"]}
                class="bac-checkbox shrink-0"
              />
              {t(@locale, @locale_version, "COV bestätigt")}
            </label>
          </div>

          <details class="group">
            <summary class="text-xs bac-text-faint cursor-pointer hover:bac-text-muted transition-colors">
              {t(@locale, @locale_version, "Erweitert")}
            </summary>
            <div class="mt-2 space-y-2">
              <div :if={ipv4_transport?(@form[:transport].value)}>
                <label class="bac-label" for={@form[:ipv4_port].id}>
                  {t(@locale, @locale_version, "UDP-Port")}
                </label>
                <.input
                  field={@form[:ipv4_port]}
                  type="number"
                  min="47808"
                  max="65535"
                  class="bac-input bac-input-sm"
                />
              </div>
              <div>
                <label class="bac-label" for={@form[:network_number].id}>
                  {t(@locale, @locale_version, "Netzwerknummer")}
                </label>
                <.input
                  field={@form[:network_number]}
                  type="number"
                  min="1"
                  max="65535"
                  class="bac-input bac-input-sm"
                />
              </div>
            </div>
          </details>

          <div
            :if={@confirm_restart?}
            class="rounded-lg border border-[var(--bac-amber)]/30 bg-[var(--bac-amber)]/5 p-3 space-y-2"
          >
            <p class="text-xs bac-text-muted leading-relaxed">
              {t(@locale, @locale_version, 
                "Diese Änderungen erfordern einen Neustart des BACnet-Stacks. Aktive COV-Abonnements werden neu aufgebaut."
              )}
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="stack_settings_cancel_restart"
                class="bac-btn bac-btn-ghost bac-btn-sm"
                id="stack-settings-cancel-btn"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="button"
                phx-click="stack_settings_confirm_restart"
                class="bac-btn bac-btn-primary bac-btn-sm"
                id="stack-settings-confirm-btn"
              >
                {t(@locale, @locale_version, "Neu starten & speichern")}
              </button>
            </div>
          </div>

          <button
            :if={not @confirm_restart?}
            type="submit"
            class="bac-btn bac-btn-primary bac-btn-sm w-full"
            id="stack-settings-apply-btn"
            disabled={@apply_disabled?}
          >
            {t(@locale, @locale_version, "Speichern")}
          </button>
        </.form>
      </div>
    </section>
    """
  end

  defp transport_options(locale, lv) do
    Enum.map(TransportResolver.supported_transports(), fn transport ->
      {transport_label(transport, locale, lv), transport}
    end)
  end

  defp transport_label("ipv4", locale, lv), do: t(locale, lv, "BACnet/IP")
  defp transport_label("mstp", locale, lv), do: t(locale, lv, "BACnet MS/TP")
  defp transport_label(other, _locale, _lv), do: other

  defp interface_label("mstp", locale, lv), do: t(locale, lv, "Serieller Port")
  defp interface_label(_interface_label, locale, lv), do: t(locale, lv, "Netzwerkschnittstelle")

  defp interface_select_options(options) do
    Enum.map(options, fn %{value: value, label: label} -> {label, value} end)
  end

  defp baud_rate_options(locale, lv) do
    auto = {t(locale, lv, "Auto"), "auto"}

    rates =
      for rate <- [9600, 19_200, 38_400, 57_600, 76_800, 115_200] do
        label = Integer.to_string(rate)
        {label, label}
      end

    [auto | rates]
  end

  defp mstp_transport?("mstp"), do: true
  defp mstp_transport?(_mstp_transport), do: false

  defp ipv4_transport?("ipv4"), do: true
  defp ipv4_transport?(_ipv4_transport), do: false

  defp interface_error_label(:no_network_interfaces, locale, lv),
    do: t(locale, lv, "Keine Netzwerkschnittstellen gefunden.")

  defp interface_error_label(:no_serial_ports, locale, lv),
    do: t(locale, lv, "Keine seriellen Ports gefunden.")

  defp interface_error_label(_no_network_interfaces, locale, lv),
    do: t(locale, lv, "Schnittstelle nicht verfügbar.")

  defp stack_status_label(%{running?: true}, locale, lv), do: t(locale, lv, "Aktiv")

  defp stack_status_label(%{last_error: nil}, locale, lv),
    do: t(locale, lv, "Offline")

  defp stack_status_label(_status, locale, lv), do: t(locale, lv, "Offline")

  defp stack_status_badge_class(%{running?: true}), do: "bac-badge-success"
  defp stack_status_badge_class(%{last_error: nil}), do: "bac-badge-ghost"
  defp stack_status_badge_class(_status), do: "bac-badge-warning"

  defp stack_error_message(%{running?: true}), do: nil
  defp stack_error_message(%{last_error: nil}), do: nil

  defp stack_error_message(%{last_error: reason}) do
    ErrorMessage.format_reason(reason)
  end
end
