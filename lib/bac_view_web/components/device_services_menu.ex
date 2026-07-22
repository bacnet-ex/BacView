defmodule BacViewWeb.DeviceServicesMenu do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:device_id, :integer, required: true)
  attr(:menu, :map, default: nil)
  attr(:class, :string, default: "")

  def trigger(assigns) do
    assigns = assign(assigns, :open?, menu_open?(assigns.menu, assigns.device_id))

    ~H"""
    <button
      type="button"
      id={"device-services-trigger-#{@device_id}"}
      phx-click="toggle_device_services_menu"
      phx-value-device-id={@device_id}
      class={[
        "bac-btn bac-btn-ghost bac-btn-icon bac-device-services-trigger",
        @class
      ]}
      aria-haspopup="menu"
      aria-expanded={to_string(@open?)}
      aria-controls={if(@open?, do: "device-services-menu-#{@device_id}")}
      title={t(@locale, @locale_version, "Gerätedienste")}
      aria-label={t(@locale, @locale_version, "Gerätedienste")}
    >
      <.icon name="hero-ellipsis-vertical" class="size-4" />
    </button>
    """
  end

  attr(:menu, :map, default: nil)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def panel(assigns) do
    ~H"""
    <div
      :if={@menu}
      id={"device-services-menu-#{@menu.device_id}"}
      phx-hook="FilterMenu"
      data-trigger-id={"device-services-trigger-#{@menu.device_id}"}
      data-close-event="close_device_services_menu"
      class="bac-filter-menu bac-device-services-menu"
    >
      <div class="bac-filter-menu-header">
        <p class="text-xs font-semibold text-[var(--bac-text)]">
          {t(@locale, @locale_version, "Gerätedienste")}
        </p>
      </div>
      <ul class="bac-filter-menu-list">
        <li class="bac-filter-menu-item">
          <button
            type="button"
            id={"device-services-scan-#{@menu.device_id}"}
            phx-click="scan_device"
            phx-value-device-id={@menu.device_id}
            class="w-full text-left text-sm"
          >
            {t(@locale, @locale_version, "Gerät scannen")}
          </button>
        </li>
        <li class="bac-filter-menu-item">
          <button
            type="button"
            phx-click="open_device_service_modal"
            phx-value-service="time_sync"
            phx-value-device-id={@menu.device_id}
            class="w-full text-left text-sm"
          >
            {t(@locale, @locale_version, "Zeitsynchronisation")}
          </button>
        </li>
        <li class="bac-filter-menu-item">
          <button
            type="button"
            phx-click="open_device_service_modal"
            phx-value-service="dcc"
            phx-value-device-id={@menu.device_id}
            class="w-full text-left text-sm"
          >
            {t(@locale, @locale_version, "Gerätekommunikation steuern")}
          </button>
        </li>
        <li class="bac-filter-menu-item">
          <button
            type="button"
            phx-click="open_device_service_modal"
            phx-value-service="reinitialize"
            phx-value-device-id={@menu.device_id}
            class="w-full text-left text-sm"
          >
            {t(@locale, @locale_version, "Gerät neu initialisieren")}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp menu_open?(%{device_id: device_id}, device_id), do: true
  defp menu_open?(_device_id, _menu_open2), do: false
end
