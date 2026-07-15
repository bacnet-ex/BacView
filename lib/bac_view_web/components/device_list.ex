defmodule BacViewWeb.DeviceList do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Address
  alias BacView.BACnet.VendorNames
  alias BacView.NaturalSort
  alias BacViewWeb.DeviceBadgeCounts
  alias BacViewWeb.DeviceServicesMenu
  alias BacViewWeb.SearchQuery

  @sort_columns ~w(name vendor address instance status objects)

  attr(:devices, :list, required: true)
  attr(:vendor_names, :map, required: true)
  attr(:scanning, :boolean, default: false)
  attr(:view, :atom, default: :grid, values: [:grid, :table])
  attr(:search, :string, default: "")
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:device_service_menu, :map, default: nil)
  attr(:device_badge_counts, :map, default: DeviceBadgeCounts.empty())

  def device_list(assigns) do
    assigns =
      assign(
        assigns,
        :filtered,
        list_devices(
          assigns.devices,
          assigns.search,
          assigns.vendor_names,
          assigns.sort_by,
          assigns.sort_dir,
          assigns.view,
          assigns.locale,
          assigns.locale_version
        )
      )

    ~H"""
    <div class="space-y-4">
      <div class="bac-device-toolbar">
        <input
          id="device-search"
          type="search"
          name="search"
          value={@search}
          placeholder={t(@locale, @locale_version, "Geräte filtern… (-Begriff zum Ausschliessen)")}
          phx-keyup="search_devices"
          phx-debounce="200"
          class="bac-input bac-input-sm flex-1 max-w-md"
        />

        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            phx-click="clear_devices"
            class="bac-btn bac-btn-ghost bac-btn-sm"
            id="device-list-clear-btn"
            disabled={@devices == [] and not @scanning}
          >
            <.icon name="hero-trash" class="size-4" />
            <span>{t(@locale, @locale_version, "Geräteliste leeren")}</span>
          </button>

          <div class="bac-view-toggle" role="group" aria-label={t(@locale, @locale_version, "Ansicht")}>
          <button
            id="device-view-grid"
            type="button"
            phx-click="set_device_view"
            phx-value-view="grid"
            class={["bac-view-toggle-btn", @view == :grid && "bac-view-toggle-active"]}
            aria-pressed={to_string(@view == :grid)}
          >
            <.icon name="hero-squares-2x2" class="size-4" />
            <span>{t(@locale, @locale_version, "Kacheln")}</span>
          </button>
          <button
            id="device-view-table"
            type="button"
            phx-click="set_device_view"
            phx-value-view="table"
            class={["bac-view-toggle-btn", @view == :table && "bac-view-toggle-active"]}
            aria-pressed={to_string(@view == :table)}
          >
            <.icon name="hero-table-cells" class="size-4" />
            <span>{t(@locale, @locale_version, "Tabelle")}</span>
          </button>
          </div>
        </div>
      </div>

      <p :if={@search != "" && @devices != []} class="text-xs bac-text-faint">
        {t(@locale, @locale_version, "%{shown} von %{total} Geräten", shown: length(@filtered), total: length(@devices))}
      </p>

      <.empty_state
        :if={@devices == []}
        locale={@locale}
        locale_version={@locale_version}
      />

      <.no_matches
        :if={@devices != [] && @filtered == []}
        locale={@locale}
        locale_version={@locale_version}
      />

      <div :if={@view == :grid && @filtered != []} id="device-list-grid" class="bac-device-grid">
        <.device_card
          :for={device <- @filtered}
          device={device}
          vendor_names={@vendor_names}
          device_service_menu={@device_service_menu}
          device_badge_counts={@device_badge_counts}
          locale={@locale}
          locale_version={@locale_version}
        />
      </div>

      <.device_table
        :if={@view == :table && @filtered != []}
        devices={@filtered}
        vendor_names={@vendor_names}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        device_service_menu={@device_service_menu}
        locale={@locale}
        locale_version={@locale_version}
      />
    </div>
    """
  end

  attr(:device, :map, required: true)
  attr(:vendor_names, :map, required: true)
  attr(:device_service_menu, :map, default: nil)
  attr(:device_badge_counts, :map, default: DeviceBadgeCounts.empty())
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp device_card(assigns) do
    assigns =
      assign(
        assigns,
        :alarm_count,
        DeviceBadgeCounts.alarm_count(assigns.device_badge_counts, assigns.device.id)
      )

    assigns =
      assign(
        assigns,
        :cov_count,
        DeviceBadgeCounts.cov_count(assigns.device_badge_counts, assigns.device.id)
      )

    ~H"""
    <div id={"device-card-#{@device.id}"} class="bac-device-card">
      <div class="bac-device-card-header">
        <.link
          navigate={~p"/devices/#{@device.id}"}
          class="flex-1 min-w-0 block overflow-hidden"
          title={device_name(@device, @locale, @locale_version)}
        >
          <h3 class="bac-device-card-title truncate">
            {device_name(@device, @locale, @locale_version)}
          </h3>
          <p :if={device_description(@device)} class="text-xs bac-text-muted truncate mt-0.5">
            {device_description(@device)}
          </p>
        </.link>
        <div class="flex items-center gap-1 shrink-0 self-start">
          <span class={status_badge_class(@device.status)}>
            {status_label(@device.status, @locale, @locale_version)}
          </span>
          <DeviceServicesMenu.trigger
            device_id={@device.id}
            menu={@device_service_menu}
            locale={@locale}
            locale_version={@locale_version}
          />
        </div>
      </div>

      <.link navigate={~p"/devices/#{@device.id}"} class="block flex-1">
        <p class="bac-device-card-vendor">
          {VendorNames.label(@vendor_names, @device.vendor_id)}
        </p>

        <p class="bac-mono text-xs bac-text-faint">{device_address_label(@device)}</p>

        <div class="bac-device-card-meta">
          <span class="bac-badge bac-badge-sm bac-badge-accent">
            ID {@device.instance}
          </span>
          <span :if={@device.object_count} class="bac-badge bac-badge-sm">
            {@device.object_count} {t(@locale, @locale_version, "Objekte")}
          </span>
          <span
            :if={@alarm_count > 0}
            class="bac-badge bac-badge-sm bac-badge-error"
            title={t(@locale, @locale_version, "%{count} aktive Alarme", count: @alarm_count)}
          >
            <.icon name="hero-bell-alert" class="size-3" />
            {@alarm_count}
          </span>
          <span
            :if={@cov_count > 0}
            class="bac-badge bac-badge-sm bac-badge-success"
            title={t(@locale, @locale_version, "%{count} COV aktiv", count: @cov_count)}
          >
            <.icon name="hero-signal" class="size-3" />
            {@cov_count}
          </span>
        </div>
      </.link>
    </div>
    """
  end

  attr(:devices, :list, required: true)
  attr(:vendor_names, :map, required: true)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:device_service_menu, :map, default: nil)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp device_table(assigns) do
    ~H"""
    <div class="bac-table-wrap">
      <table class="bac-table" id="device-list-table">
        <thead>
          <tr>
            <th>
              <.sort_header column="name" label={t(@locale, @locale_version, "Name")} sort_by={@sort_by} sort_dir={@sort_dir} />
            </th>
            <th>
              <.sort_header column="vendor" label={t(@locale, @locale_version, "Hersteller")} sort_by={@sort_by} sort_dir={@sort_dir} />
            </th>
            <th>
              <.sort_header column="address" label={t(@locale, @locale_version, "Adresse")} sort_by={@sort_by} sort_dir={@sort_dir} />
            </th>
            <th>
              <.sort_header column="instance" label={t(@locale, @locale_version, "Geräte-ID")} sort_by={@sort_by} sort_dir={@sort_dir} />
            </th>
            <th>
              <.sort_header column="status" label={t(@locale, @locale_version, "Status")} sort_by={@sort_by} sort_dir={@sort_dir} />
            </th>
            <th>
              <.sort_header column="objects" label={t(@locale, @locale_version, "Objekte")} sort_by={@sort_by} sort_dir={@sort_dir} />
            </th>
            <th class="w-10" aria-label={t(@locale, @locale_version, "Aktionen")}></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={device <- @devices}
            id={"device-row-#{device.id}"}
            class="bac-row-clickable"
          >
            <td class="font-medium text-[var(--bac-text)] max-w-[16rem]">
              <.link
                navigate={~p"/devices/#{device.id}"}
                class="block truncate"
                title={device_name(device, @locale, @locale_version)}
              >
                {device_name(device, @locale, @locale_version)}
              </.link>
            </td>
            <td class="text-[var(--bac-text-muted)]">
              {VendorNames.label(@vendor_names, device.vendor_id)}
            </td>
            <td class="bac-mono text-xs">{device_address_label(device)}</td>
            <td class="bac-mono text-xs">{device.instance}</td>
            <td>
              <span class={status_badge_class(device.status)}>
                {status_label(device.status, @locale, @locale_version)}
              </span>
            </td>
            <td class="bac-text-muted">{object_count_label(device.object_count)}</td>
            <td>
              <DeviceServicesMenu.trigger
                device_id={device.id}
                menu={@device_service_menu}
                locale={@locale}
                locale_version={@locale_version}
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp empty_state(assigns) do
    ~H"""
    <div class="bac-empty-state">
      <div class="bac-empty-state-icon">
        <.icon name="hero-rss" class="size-7" />
      </div>
      <p class="bac-empty-state-title">{t(@locale, @locale_version, "Noch keine Geräte gefunden")}</p>
      <p class="bac-empty-state-text">
        {t(@locale, @locale_version, "Starten Sie einen Netzwerkscan in der Seitenleiste, um BACnet-Geräte zu entdecken.")}
      </p>
    </div>
    """
  end

  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp no_matches(assigns) do
    ~H"""
    <div class="bac-empty-state py-12">
      <p class="bac-empty-state-title">{t(@locale, @locale_version, "Keine Treffer")}</p>
      <p class="bac-empty-state-text">
        {t(@locale, @locale_version, "Passen Sie den Suchbegriff an, um Geräte einzugrenzen.")}
      </p>
    </div>
    """
  end

  attr(:column, :string, required: true)
  attr(:label, :string, required: true)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)

  def sort_header(assigns) do
    ~H"""
    <button
      type="button"
      id={"device-sort-#{@column}"}
      phx-click="sort_devices"
      phx-value-column={@column}
      class={[
        "bac-sort-header",
        @sort_by == @column && "bac-sort-header-active"
      ]}
      aria-sort={if @sort_by == @column, do: Atom.to_string(@sort_dir), else: "none"}
    >
      <span>{@label}</span>
      <.icon
        :if={@sort_by == @column && @sort_dir == :asc}
        name="hero-chevron-up"
        class="size-3.5"
      />
      <.icon
        :if={@sort_by == @column && @sort_dir == :desc}
        name="hero-chevron-down"
        class="size-3.5"
      />
      <.icon
        :if={@sort_by != @column}
        name="hero-chevron-up-down"
        class="size-3.5 opacity-35"
      />
    </button>
    """
  end

  @doc false
  def list_devices(
        devices,
        search,
        vendor_names,
        sort_by,
        sort_dir,
        view,
        locale \\ "de",
        locale_version \\ 0
      ) do
    devices
    |> filtered_devices(search, vendor_names, locale, locale_version)
    |> maybe_sorted(sort_by, sort_dir, vendor_names, view, locale, locale_version)
  end

  @doc false
  def filtered_devices(devices, search, vendor_names, locale \\ "de", locale_version \\ 0) do
    Enum.filter(devices, &matches_search?(&1, search, vendor_names, locale, locale_version))
  end

  @doc false
  def sorted_devices(
        devices,
        sort_by,
        sort_dir,
        vendor_names,
        locale \\ "de",
        locale_version \\ 0
      )

  def sorted_devices(devices, sort_by, sort_dir, vendor_names, locale, locale_version)
      when sort_by in @sort_columns do
    Enum.sort_by(devices, &sort_key(&1, sort_by, vendor_names, locale, locale_version), sort_dir)
  end

  def sorted_devices(devices, _sort_by, _sort_dir, _vendor_names, _locale, _locale_version),
    do: devices

  @doc false
  def normalize_sort_column(column) when column in @sort_columns, do: column
  def normalize_sort_column(_column), do: nil

  @doc false
  def normalize_sort_dir(dir) when dir in [:asc, :desc], do: dir
  def normalize_sort_dir("asc"), do: :asc
  def normalize_sort_dir("desc"), do: :desc
  def normalize_sort_dir(_dir), do: :asc

  @doc false
  def normalize_view("grid"), do: :grid
  def normalize_view("table"), do: :table
  def normalize_view(view) when view in [:grid, :table], do: view
  def normalize_view(_view), do: :grid

  @doc false
  def toggle_sort(nil, _sort_dir, column), do: {column, :asc}
  def toggle_sort(column, :asc, column), do: {column, :desc}
  def toggle_sort(column, :desc, column), do: {column, :asc}
  def toggle_sort(_sort_by, _sort_dir, column), do: {column, :asc}

  defp maybe_sorted(devices, sort_by, sort_dir, vendor_names, :table, locale, locale_version) do
    sorted_devices(devices, sort_by, sort_dir, vendor_names, locale, locale_version)
  end

  defp maybe_sorted(devices, _sort_by, _sort_dir, _vendor_names, :grid, _locale, _locale_version),
    do: devices

  defp matches_search?(device, search, vendor_names, locale, locale_version) do
    SearchQuery.haystack_matches?(
      search,
      device_search_haystack(device, vendor_names, locale, locale_version)
    )
  end

  defp device_search_haystack(device, vendor_names, locale, locale_version) do
    [
      device_name(device, locale, locale_version),
      VendorNames.label(vendor_names, device.vendor_id),
      device_address_label(device),
      to_string(device.instance),
      status_label(device.status, locale, locale_version),
      object_count_label(device.object_count)
    ]
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp sort_key(device, "name", _vendor_names, locale, locale_version),
    do: nullable_string_key(device_name(device, locale, locale_version))

  defp sort_key(device, "vendor", vendor_names, _locale, _locale_version),
    do: nullable_string_key(VendorNames.label(vendor_names, device.vendor_id))

  defp sort_key(device, "address", _vendor_names, _locale, _locale_version),
    do: Address.destination_sort_key(device.address || {device.ip, device.port})

  defp sort_key(device, "instance", _vendor_names, _locale, _locale_version),
    do: device.instance

  defp sort_key(device, "status", _vendor_names, _locale, _locale_version),
    do: status_sort_key(device.status)

  defp sort_key(device, "objects", _vendor_names, _locale, _locale_version),
    do: objects_sort_key(device.object_count)

  defp nullable_string_key(nil), do: {1, NaturalSort.key("")}
  defp nullable_string_key(value), do: {0, NaturalSort.key(value)}

  defp device_address_label(device), do: Address.format_device_address(device)

  defp status_sort_key(:loaded), do: 0
  defp status_sort_key(:discovered), do: 1
  defp status_sort_key(_loaded), do: 2

  defp objects_sort_key(nil), do: -1
  defp objects_sort_key(count) when is_integer(count), do: count

  defp device_name(device, locale, locale_version) do
    device.name ||
      t(locale, locale_version, "Gerät %{id}", id: device.instance)
  end

  defp device_description(%{description: description})
       when is_binary(description) and description != "",
       do: description

  defp device_description(_device), do: nil

  defp object_count_label(nil), do: "-"
  defp object_count_label(count) when is_integer(count), do: Integer.to_string(count)

  defp status_label(:loaded, locale, locale_version),
    do: t(locale, locale_version, "Geladen")

  defp status_label(:discovered, locale, locale_version),
    do: t(locale, locale_version, "Entdeckt")

  defp status_label(_loaded, locale, locale_version),
    do: t(locale, locale_version, "Unbekannt")

  defp status_badge_class(status) do
    [
      "bac-badge bac-badge-sm shrink-0",
      (status == :loaded && "bac-badge-success") || "bac-badge-ghost"
    ]
  end
end
