defmodule BacViewWeb.DeviceServiceModals do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:modal, :map, default: nil)
  attr(:busy, :boolean, default: false)

  def modals(assigns) do
    ~H"""
    <div :if={@modal} id="device-service-modal" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_device_service_modal"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal" role="dialog" aria-modal="true">
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {modal_subtitle(@modal.type, @locale, @locale_version)}
              </p>
              <h2 class="font-semibold text-base mt-0.5">
                {modal_title(@modal.type, @locale, @locale_version)}
              </h2>
            </div>
            <button
              type="button"
              phx-click="close_device_service_modal"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={%{}}
            as={:service}
            id="device-service-form"
            phx-change="device_service_form_change"
            phx-submit="execute_device_service"
          >
            <%= case @modal.type do %>
              <% :time_sync -> %>
                <fieldset class="space-y-2">
                  <legend class="text-sm font-medium text-[var(--bac-text)]">
                    {t(@locale, @locale_version, "Zeitmodus")}
                  </legend>
                  <label class="flex items-center gap-2 text-sm cursor-pointer">
                    <input
                      type="radio"
                      name="time_mode"
                      value="local"
                      checked={@modal.form["time_mode"] == "local"}
                      class="bac-checkbox"
                    />
                    <span>{t(@locale, @locale_version, "Lokale Zeit")}</span>
                  </label>
                  <label class="flex items-center gap-2 text-sm cursor-pointer">
                    <input
                      type="radio"
                      name="time_mode"
                      value="utc"
                      checked={@modal.form["time_mode"] == "utc"}
                      class="bac-checkbox"
                    />
                    <span>{t(@locale, @locale_version, "UTC")}</span>
                  </label>
                </fieldset>
              <% :dcc -> %>
                <div class="space-y-3">
                  <div class="space-y-1.5">
                    <label for="dcc-state" class="text-xs bac-text-faint">
                      {t(@locale, @locale_version, "Enable/Disable")}
                    </label>
                    <select
                      id="dcc-state"
                      name="state"
                      class="bac-input bac-input-sm w-full"
                    >
                      <option value="enable" selected={@modal.form["state"] == "enable"}>
                        {t(@locale, @locale_version, "Kommunikation aktivieren")}
                      </option>
                      <option value="disable" selected={@modal.form["state"] == "disable"}>
                        {t(@locale, @locale_version, "Kommunikation deaktivieren")}
                      </option>
                      <option
                        value="disable_initiation"
                        selected={@modal.form["state"] == "disable_initiation"}
                      >
                        {t(@locale, @locale_version, "Initiierung deaktivieren")}
                      </option>
                    </select>
                  </div>
                  <div class="space-y-1.5">
                    <label for="dcc-duration" class="text-xs bac-text-faint">
                      {t(@locale, @locale_version, "Dauer (Minuten, leer = unbegrenzt)")}
                    </label>
                    <input
                      id="dcc-duration"
                      type="number"
                      name="time_duration"
                      min="0"
                      max="65535"
                      value={@modal.form["time_duration"]}
                      placeholder={t(@locale, @locale_version, "unbegrenzt")}
                      class="bac-input bac-input-sm w-full"
                    />
                  </div>
                  <div class="space-y-1.5">
                    <label for="dcc-password" class="text-xs bac-text-faint">
                      {t(@locale, @locale_version, "Passwort (optional)")}
                    </label>
                    <input
                      id="dcc-password"
                      type="password"
                      name="password"
                      value={@modal.form["password"]}
                      maxlength="20"
                      autocomplete="off"
                      class="bac-input bac-input-sm w-full"
                    />
                  </div>
                </div>
              <% :reinitialize -> %>
                <div class="space-y-3">
                  <div class="space-y-1.5">
                    <label for="reinit-state" class="text-xs bac-text-faint">
                      {t(@locale, @locale_version, "Neustart-Typ")}
                    </label>
                    <select
                      id="reinit-state"
                      name="reinitialized_state"
                      class="bac-input bac-input-sm w-full"
                    >
                      <option
                        value="warmstart"
                        selected={@modal.form["reinitialized_state"] == "warmstart"}
                      >
                        {t(@locale, @locale_version, "Warmstart")}
                      </option>
                      <option
                        value="coldstart"
                        selected={@modal.form["reinitialized_state"] == "coldstart"}
                      >
                        {t(@locale, @locale_version, "Coldstart")}
                      </option>
                      <option
                        value="startbackup"
                        selected={@modal.form["reinitialized_state"] == "startbackup"}
                      >
                        {t(@locale, @locale_version, "Backup starten")}
                      </option>
                      <option
                        value="endbackup"
                        selected={@modal.form["reinitialized_state"] == "endbackup"}
                      >
                        {t(@locale, @locale_version, "Backup beenden")}
                      </option>
                      <option
                        value="startrestore"
                        selected={@modal.form["reinitialized_state"] == "startrestore"}
                      >
                        {t(@locale, @locale_version, "Wiederherstellung starten")}
                      </option>
                      <option
                        value="endrestore"
                        selected={@modal.form["reinitialized_state"] == "endrestore"}
                      >
                        {t(@locale, @locale_version, "Wiederherstellung beenden")}
                      </option>
                      <option
                        value="abortrestore"
                        selected={@modal.form["reinitialized_state"] == "abortrestore"}
                      >
                        {t(@locale, @locale_version, "Wiederherstellung abbrechen")}
                      </option>
                      <option
                        value="activate_changes"
                        selected={@modal.form["reinitialized_state"] == "activate_changes"}
                      >
                        {t(@locale, @locale_version, "Änderungen aktivieren")}
                      </option>
                    </select>
                  </div>
                  <div class="space-y-1.5">
                    <label for="reinit-password" class="text-xs bac-text-faint">
                      {t(@locale, @locale_version, "Passwort (optional)")}
                    </label>
                    <input
                      id="reinit-password"
                      type="password"
                      name="password"
                      value={@modal.form["password"]}
                      maxlength="20"
                      autocomplete="off"
                      class="bac-input bac-input-sm w-full"
                    />
                  </div>
                </div>
            <% end %>

            <div class="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                phx-click="close_device_service_modal"
                class="bac-btn bac-btn-ghost bac-btn-sm"
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                disabled={@busy}
                class="bac-btn bac-btn-primary bac-btn-sm"
              >
                <%= if @busy do %>
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                <% end %>
                {t(@locale, @locale_version, "Ausführen")}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp modal_title(:time_sync, locale, v),
    do: BacViewWeb.GettextLC.t(locale, v, "Zeitsynchronisation")

  defp modal_title(:dcc, locale, v),
    do: BacViewWeb.GettextLC.t(locale, v, "Gerätekommunikation steuern")

  defp modal_title(:reinitialize, locale, v),
    do: BacViewWeb.GettextLC.t(locale, v, "Gerät neu initialisieren")

  defp modal_title(_time_sync, locale, v), do: BacViewWeb.GettextLC.t(locale, v, "Gerätedienst")

  defp modal_subtitle(_type, locale, v), do: BacViewWeb.GettextLC.t(locale, v, "Gerätedienst")
end
