defmodule BacViewWeb.ReadPropertyModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.BacnetUri
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacViewWeb.PropertyValue
  alias BacViewWeb.ReadPropertyLive

  attr(:state, :map, default: nil)

  def modal(assigns) do
    assigns =
      assigns
      |> assign(:object_type_options, BacnetUri.object_type_options())
      |> assign(:property_options, BacnetUri.property_identifier_options())

    ~H"""
    <div :if={@state} id="read-property-modal" class="bac-modal-backdrop" phx-hook="FocusFirstInput">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_read_property"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal bac-modal-lg bac-modal-constrain" role="dialog" aria-modal="true">
        <div class="bac-modal-body">
          <div class="flex items-start justify-between gap-3 shrink-0">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "BACnet-Dienst")}
              </p>
              <h2 class="font-semibold text-base mt-0.5">
                {t(@locale, @locale_version, "Eigenschaft lesen")}
              </h2>
            </div>
            <button
              type="button"
              phx-click="close_read_property"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={@state.form}
            id="read-property-form"
            phx-change="read_property_form_change"
            phx-submit="read_property_execute"
            class="space-y-3 shrink-0"
          >
            <div class="space-y-1.5">
              <label class="bac-label" for={@state.form[:uri].id}>
                {t(@locale, @locale_version, "BACnet-URI")}
              </label>
              <.input
                field={@state.form[:uri]}
                type="text"
                placeholder="bacnet://123/analog-value,1/present-value"
                class="bac-input bac-input-sm bac-mono"
                autocomplete="off"
                data-autofocus
                disabled={@state.busy}
              />
              <p id="read-property-uri-hint" class="text-xs bac-text-faint">
                {t(
                  @locale,
                  @locale_version,
                  "Eine gültige URI füllt die Felder. Gelesen wird mit den Feldern unten, inklusive Ziel."
                )}
              </p>
              <p
                :if={locator(@state) == "address"}
                id="read-property-address-uri-hint"
                class="text-xs bac-text-faint"
              >
                {t(
                  @locale,
                  @locale_version,
                  "Ziel ist die Adresse. Die URI beschreibt nur Objekt und Eigenschaft."
                )}
              </p>
              <p :if={@state.uri_error} id="read-property-uri-error" class="text-xs text-[var(--bac-rose)]">
                {ErrorMessage.format_reason(@state.uri_error)}
              </p>
            </div>

            <fieldset class="space-y-2">
              <legend class="text-sm font-medium text-[var(--bac-text)]">
                {t(@locale, @locale_version, "Ziel")}
              </legend>
              <label class="flex items-center gap-2 text-sm cursor-pointer">
                <input
                  type="radio"
                  id="read-property-locator-device-id"
                  name={@state.form[:locator].name}
                  value="device_id"
                  checked={locator(@state) == "device_id"}
                  class="bac-checkbox"
                  disabled={@state.busy}
                />
                <span>{t(@locale, @locale_version, "Geräte-ID")}</span>
              </label>
              <label class="flex items-center gap-2 text-sm cursor-pointer">
                <input
                  type="radio"
                  id="read-property-locator-address"
                  name={@state.form[:locator].name}
                  value="address"
                  checked={locator(@state) == "address"}
                  class="bac-checkbox"
                  disabled={@state.busy}
                />
                <span>{t(@locale, @locale_version, "Adresse")}</span>
              </label>
            </fieldset>

            <div class={["space-y-1.5", locator(@state) != "device_id" && "hidden"]}>
              <label class="bac-label" for={@state.form[:device_id].id}>
                {t(@locale, @locale_version, "Geräte-ID")}
              </label>
              <.input
                field={@state.form[:device_id]}
                type="number"
                min="0"
                max="4194303"
                step="1"
                class="bac-input bac-input-sm"
                disabled={@state.busy}
              />
            </div>

            <div class={["space-y-1.5", locator(@state) != "address" && "hidden"]}>
              <label class="bac-label" for={@state.form[:address].id}>
                {t(@locale, @locale_version, "Adresse")}
              </label>
              <.input
                field={@state.form[:address]}
                type="text"
                placeholder={address_placeholder(@state.transport)}
                class="bac-input bac-input-sm bac-mono"
                autocomplete="off"
                disabled={@state.busy}
              />
              <p class="text-xs bac-text-faint">
                {address_help(@state.transport, @locale, @locale_version)}
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="space-y-1.5">
                <label class="bac-label" for={@state.form[:object_type].id}>
                  {t(@locale, @locale_version, "Objekttyp")}
                </label>
                <.input
                  field={@state.form[:object_type]}
                  type="text"
                  list="read-property-object-types"
                  placeholder="analog-value"
                  class="bac-input bac-input-sm bac-mono"
                  autocomplete="off"
                  disabled={@state.busy}
                />
                <datalist id="read-property-object-types">
                  <option :for={name <- @object_type_options} value={name} />
                </datalist>
              </div>
              <div class="space-y-1.5">
                <label class="bac-label" for={@state.form[:instance].id}>
                  {t(@locale, @locale_version, "Instanz")}
                </label>
                <.input
                  field={@state.form[:instance]}
                  type="number"
                  min="0"
                  max="4194303"
                  step="1"
                  class="bac-input bac-input-sm"
                  disabled={@state.busy}
                />
              </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="space-y-1.5">
                <label class="bac-label" for={@state.form[:property].id}>
                  {t(@locale, @locale_version, "Eigenschaft")}
                </label>
                <.input
                  field={@state.form[:property]}
                  type="text"
                  list="read-property-properties"
                  placeholder="present-value"
                  class="bac-input bac-input-sm bac-mono"
                  autocomplete="off"
                  disabled={@state.busy}
                />
                <datalist id="read-property-properties">
                  <option :for={name <- @property_options} value={name} />
                </datalist>
              </div>
              <div class="space-y-1.5">
                <label class="bac-label" for={@state.form[:array_index].id}>
                  {t(@locale, @locale_version, "Array-Index")}
                </label>
                <.input
                  field={@state.form[:array_index]}
                  type="number"
                  min="0"
                  step="1"
                  class="bac-input bac-input-sm"
                  disabled={@state.busy}
                />
                <p class="text-xs bac-text-faint">
                  {t(@locale, @locale_version, "Optional")}
                </p>
              </div>
            </div>

            <div class="flex justify-end gap-2 pt-1">
              <button
                type="button"
                phx-click="close_read_property"
                class="bac-btn bac-btn-ghost bac-btn-sm"
                disabled={@state.busy}
              >
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                id="read-property-submit"
                class={["bac-btn bac-btn-primary bac-btn-sm", @state.busy && "opacity-80"]}
                disabled={@state.busy}
                aria-busy={to_string(@state.busy)}
              >
                <.icon
                  name="hero-arrow-path"
                  class={if(@state.busy, do: "size-3.5 animate-spin", else: "size-3.5")}
                />
                {t(@locale, @locale_version, "Lesen")}
              </button>
            </div>
          </.form>

          <p
            :if={@state.error}
            id="read-property-error"
            class="text-sm text-[var(--bac-rose)] shrink-0"
            role="alert"
          >
            {@state.error}
          </p>

          <div
            :if={@state.result}
            id="read-property-result"
            class="bac-read-property-result rounded-lg border border-[var(--bac-border)] bg-[var(--bac-bg-elevated)] p-3 space-y-2"
          >
            <p class="text-xs bac-text-faint uppercase tracking-wide shrink-0">
              {t(@locale, @locale_version, "Ergebnis")}
            </p>
            <p class="bac-mono text-xs bac-text-faint shrink-0">
              {ReadPropertyLive.destination_label(@state.result.destination)}
              · {@state.result.object.type}:{@state.result.object.instance}
              · {identifier_label(@state.result.property)}
              <%= if @state.result.array_index do %>
                [{@state.result.array_index}]
              <% end %>
            </p>
            <div id="read-property-result-value" class="bac-read-property-result-value text-sm mt-1 pr-1">
              <PropertyValue.property_value
                display={@state.result.display}
                locale={@locale}
                locale_version={@locale_version}
                dom_id_prefix="read-property"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp locator(%{form: form}) do
    value = form[:locator].value
    if value in ["address", "device_id"], do: value, else: "device_id"
  end

  defp address_placeholder("mstp"), do: "0–254"
  defp address_placeholder(_transport), do: "192.168.1.10 oder 192.168.1.10:47808"

  defp address_help("mstp", locale, locale_version) do
    t(locale, locale_version, "MS/TP-MAC (0–254)")
  end

  defp address_help(_transport, locale, locale_version) do
    t(locale, locale_version, "IPv4-Adresse, Port optional (Standard 47808).")
  end

  defp identifier_label(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp identifier_label(value), do: to_string(value)
end
