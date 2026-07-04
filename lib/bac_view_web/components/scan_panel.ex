defmodule BacViewWeb.ScanPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Discovery

  attr(:form, :map, required: true)
  attr(:scanning, :boolean, default: false)
  attr(:variant, :atom, default: :sidebar, values: [:sidebar, :hero])
  attr(:id, :string, default: "scan-network-form")

  def scan_panel(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-change="scan_form_change"
      phx-submit="scan_network"
      class={[
        @variant == :sidebar && "space-y-2",
        @variant == :hero && "w-full max-w-sm mx-auto space-y-3 text-left"
      ]}
    >
      <div class={[@variant == :hero && "grid grid-cols-1 gap-3", @variant == :sidebar && "space-y-2"]}>
        <div>
          <label class="bac-label" for={@form[:timeout_ms].id}>
            {t(@locale, @locale_version, "Timeout (ms)")}
          </label>
          <.input
            field={@form[:timeout_ms]}
            type="number"
            min={Discovery.min_timeout()}
            step="100"
            class={input_class(@variant)}
            disabled={@scanning}
          />
          <p class="text-xs bac-text-faint mt-1">
            {t(@locale, @locale_version, "Minimum %{min} ms", min: Discovery.min_timeout())}
          </p>
        </div>

        <div>
          <label class="bac-label" for={@form[:target_ip].id}>
            {t(@locale, @locale_version, "Ziel-IP (optional)")}
          </label>
          <.input
            field={@form[:target_ip]}
            type="text"
            placeholder="192.168.1.100 oder 192.168.100.[31-35]"
            class={input_class(@variant)}
            disabled={@scanning}
            autocomplete="off"
          />
          <p class="text-xs bac-text-faint mt-1">
            {t(@locale, @locale_version, 
              "Leer lassen für Netzwerk-Broadcast, oder IP bzw. Bereich (z. B. 192.168.100.[31-35]) für gezieltes Who-Is."
            )}
          </p>
        </div>

        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="bac-label" for={@form[:device_id_low].id}>
              {t(@locale, @locale_version, "Geräte-ID von")}
            </label>
            <.input
              field={@form[:device_id_low]}
              type="number"
              min="0"
              max="4194303"
              step="1"
              placeholder="0"
              class={input_class(@variant)}
              disabled={@scanning}
            />
          </div>
          <div>
            <label class="bac-label" for={@form[:device_id_high].id}>
              {t(@locale, @locale_version, "Geräte-ID bis")}
            </label>
            <.input
              field={@form[:device_id_high]}
              type="number"
              min="0"
              max="4194303"
              step="1"
              placeholder="4194303"
              class={input_class(@variant)}
              disabled={@scanning}
            />
          </div>
        </div>
        <p class="text-xs bac-text-faint -mt-1">
          {t(@locale, @locale_version, "Optionaler Instanzbereich für Who-Is (0–4194303).")}
        </p>

        <div>
          <label class="bac-label" for={@form[:vendor_id].id}>
            {t(@locale, @locale_version, "Hersteller-ID (optional)")}
          </label>
          <.input
            field={@form[:vendor_id]}
            type="number"
            min="0"
            max="65535"
            step="1"
            placeholder="5"
            class={input_class(@variant)}
            disabled={@scanning}
          />
          <p class="text-xs bac-text-faint mt-1">
            {t(@locale, @locale_version, "Nur I-Am-Antworten mit dieser BACnet-Hersteller-ID übernehmen.")}
          </p>
        </div>
      </div>

      <button
        type="submit"
        disabled={@scanning}
        class={[
          "bac-btn bac-btn-primary",
          @variant == :sidebar && "bac-btn-sm w-full",
          @variant == :hero && "w-full"
        ]}
        id={"#{@id}-submit"}
      >
        <.icon :if={@scanning} name="hero-arrow-path" class="size-4 animate-spin" />
        <.icon :if={!@scanning} name="hero-magnifying-glass" class="size-4" />
        {t(@locale, @locale_version, "Netzwerk scannen")}
      </button>
    </.form>
    """
  end

  defp input_class(:sidebar), do: "bac-input bac-input-sm bac-mono w-full"
  defp input_class(:hero), do: "bac-input bac-mono w-full"
end
