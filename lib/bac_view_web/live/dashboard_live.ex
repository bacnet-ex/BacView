defmodule BacViewWeb.DashboardLive do
  @moduledoc false
  use BacViewWeb, :live_view

  alias BacView.BACnet.Discovery
  alias BacView.BACnet.ForeignRegistration
  alias BacView.BACnet.InterfaceSelection
  alias BacView.BACnet.NetworkNumber
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Stack
  alias BacView.BACnet.StackLifecycle
  alias BacView.BACnet.VendorNames

  alias BacView.Settings

  alias BacViewWeb.ActiveAlarmsAssigns
  alias BacViewWeb.ActiveAlarmsPopup
  alias BacViewWeb.ActiveCovSubscriptionsAssigns
  alias BacViewWeb.ActiveCovSubscriptionsPopup
  alias BacViewWeb.BBMDPanel
  alias BacViewWeb.DeviceList
  alias BacViewWeb.DeviceServiceModals
  alias BacViewWeb.DeviceServicesMenu
  alias BacViewWeb.LiveFlash
  alias BacViewWeb.LogViewerLive
  alias BacViewWeb.LogViewerModal
  alias BacViewWeb.ScanPanel
  alias BacViewWeb.StackSettingsPanel
  alias BacViewWeb.StackStatusPolling

  alias BacViewWeb.DeviceBadgeCounts
  alias BacViewWeb.DeviceServicesHandlers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BacView.PubSub, "devices")
      Phoenix.PubSub.subscribe(BacView.PubSub, "alarms:updates")
      Phoenix.PubSub.subscribe(BacView.PubSub, "cov:updates")
      Phoenix.PubSub.subscribe(BacView.PubSub, "bbmd:updates")
      Phoenix.PubSub.subscribe(BacView.PubSub, NetworkNumber.topic())
      Process.send_after(self(), :refresh_stack_status, StackStatusPolling.normal_poll_ms())
    end

    bbmd_status = ForeignRegistration.status()
    stack_settings = Settings.get()

    {:ok,
     socket
     |> assign(:page_title, gt("BacView"))
     |> assign(:devices, Discovery.list_devices())
     |> assign(:scanning, false)
     |> assign(:last_scan_at, nil)
     |> assign(:scan_form, scan_form())
     |> assign(:show_shortcuts, false)
     |> assign(:bbmd_status, bbmd_status)
     |> assign(:bbmd_form, bbmd_form(bbmd_status))
     |> assign_stack_settings(stack_settings)
     |> assign(:stack_status, Stack.status())
     |> assign(:stack_status_fast_poll_until, nil)
     |> assign(:stack_restart_confirm, false)
     |> assign(:stack_pending_updates, nil)
     |> assign(:learned_network_number, learned_network_number())
     |> LogViewerLive.init()
     |> assign(:vendor_names, VendorNames.names())
     |> assign(:device_view, :grid)
     |> assign(:device_search, "")
     |> assign(:device_sort_by, nil)
     |> assign(:device_sort_dir, :asc)
     |> assign(:device_badge_counts, DeviceBadgeCounts.empty())
     |> DeviceServicesHandlers.init_assigns()
     |> ActiveAlarmsAssigns.init()
     |> ActiveCovSubscriptionsAssigns.init()
     |> DeviceBadgeCounts.assign_counts()}
  end

  @impl true
  def handle_event("stack_settings_change", %{"stack" => params}, socket) do
    form_values = Map.merge(stack_form_values(socket.assigns.stack_form), params)

    {:noreply,
     refresh_stack_interfaces(socket, form_values["transport"], form_values["interface"])}
  end

  @impl true
  def handle_event("stack_settings_refresh_interfaces", _params, socket) do
    {:noreply, refresh_stack_interfaces(socket)}
  end

  @impl true
  def handle_event("stack_settings_save", %{"stack" => params}, socket) do
    case parse_stack_updates(params, socket.assigns.stack_settings) do
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, stack_settings_error(reason))}

      {:ok, updates} ->
        current = socket.assigns.stack_settings
        preview = preview_settings(current, updates)

        if Settings.stack_restart_required?(current, preview) do
          {:noreply,
           socket
           |> assign(:stack_restart_confirm, true)
           |> assign(:stack_pending_updates, updates)}
        else
          {:noreply, save_stack_settings(socket, updates)}
        end
    end
  end

  @impl true
  def handle_event("stack_restart_request", _params, socket) do
    {:noreply,
     socket
     |> assign(:stack_restart_confirm, true)
     |> assign(:stack_pending_updates, :manual)}
  end

  @impl true
  def handle_event("stack_settings_confirm_restart", _params, socket) do
    case socket.assigns.stack_pending_updates do
      nil ->
        {:noreply, assign(socket, :stack_restart_confirm, false)}

      :manual ->
        {:noreply,
         socket
         |> assign(:stack_restart_confirm, false)
         |> assign(:stack_pending_updates, nil)
         |> assign(:scanning, false)
         |> begin_fast_stack_status_poll()
         |> start_stack_restart_async()}

      updates ->
        socket = save_stack_settings(socket, updates, restart?: true)

        {:noreply,
         socket
         |> assign(:stack_restart_confirm, false)
         |> assign(:stack_pending_updates, nil)}
    end
  end

  @impl true
  def handle_event("stack_settings_cancel_restart", _params, socket) do
    {:noreply,
     socket
     |> assign(:stack_restart_confirm, false)
     |> assign(:stack_pending_updates, nil)}
  end

  @impl true
  def handle_event("open_log_viewer", _params, socket) do
    {:noreply, LogViewerLive.open(socket)}
  end

  @impl true
  def handle_event("close_log_viewer", _params, socket) do
    {:noreply, LogViewerLive.close(socket)}
  end

  @impl true
  def handle_event("log_viewer_refresh", _params, socket) do
    {:noreply, LogViewerLive.refresh(socket)}
  end

  @impl true
  def handle_event("log_viewer_clear", _params, socket) do
    {:noreply, LogViewerLive.clear(socket)}
  end

  @impl true
  def handle_event("log_viewer_filter", %{"level" => level}, socket) do
    {:noreply, LogViewerLive.filter(socket, level)}
  end

  @impl true
  def handle_event("bbmd_register", %{"bbmd" => params}, socket) do
    host = String.trim(params["bbmd_host"] || "")
    port = parse_int(params["bbmd_port"], 47_808)
    ttl = parse_int(params["bbmd_ttl"], 600)

    if host == "" do
      {:noreply, put_flash(socket, :error, gt("BBMD-Adresse ist erforderlich."))}
    else
      case ForeignRegistration.register(host, port, ttl: ttl) do
        :ok ->
          status = ForeignRegistration.status()

          {:noreply,
           socket
           |> assign(:bbmd_status, status)
           |> assign(:bbmd_form, bbmd_form(status))
           |> put_flash(:info, gt("Foreign Device Registrierung gestartet."))}

        {:error, reason} ->
          {:noreply, LiveFlash.put_error(socket, :bbmd_register, reason)}
      end
    end
  end

  @impl true
  def handle_event("bbmd_unregister", _params, socket) do
    :ok = ForeignRegistration.unregister()
    status = ForeignRegistration.status()

    {:noreply,
     socket
     |> assign(:bbmd_status, status)
     |> assign(:bbmd_form, bbmd_form(status))
     |> put_flash(:info, gt("Foreign Device abgemeldet."))}
  end

  @impl true
  def handle_event("scan_form_restore", %{"scan" => scan_params}, socket) do
    form = scan_form(scan_params)
    sync_discovery_acceptance_filters(form)
    {:noreply, assign(socket, :scan_form, form)}
  end

  def handle_event("scan_form_change", %{"scan" => scan_params}, socket) do
    form = scan_form(scan_params)
    sync_discovery_acceptance_filters(form)
    {:noreply, assign(socket, :scan_form, form)}
  end

  @impl true
  def handle_event("scan_network", params, socket) do
    scan_params =
      case Map.get(params, "scan") do
        %{} = scan -> scan
        _handle_event -> scan_form_params(socket.assigns.scan_form)
      end

    with {:ok, opts} <- Discovery.parse_scan_params(scan_params),
         :ok <- Discovery.scan_async(self(), opts) do
      Discovery.set_acceptance_filters(opts)

      {:noreply,
       socket
       |> assign(:scanning, true)
       |> assign(:scan_form, scan_form(scan_params))}
    else
      {:error, :invalid_timeout} ->
        {:noreply, put_flash(socket, :error, gt("Ungültiges Timeout."))}

      {:error, {:timeout_too_low, min}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gt("Timeout muss mindestens %{min} ms betragen.", min: min)
         )}

      {:error, :invalid_host} ->
        {:noreply, put_flash(socket, :error, gt("Ungültige IP-Adresse."))}

      {:error, {:too_many_targets, max}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gt("Zu viele Ziel-IP-Adressen (max. %{max}).", max: max)
         )}

      {:error, :invalid_device_id} ->
        {:noreply, put_flash(socket, :error, gt("Ungültige Geräte-Instanz (0–4194303)."))}

      {:error, :invalid_device_range} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gt("Gerätebereich ungültig: „von“ muss kleiner oder gleich „bis“ sein.")
         )}

      {:error, :invalid_vendor_id} ->
        {:noreply, put_flash(socket, :error, gt("Ungültige Hersteller-ID (0–65535)."))}
    end
  end

  @impl true
  def handle_event("global_keydown", params, socket) do
    cond do
      BacViewWeb.Shortcuts.ignore_global_shortcut?(params, socket.assigns) ->
        {:noreply, socket}

      BacViewWeb.Shortcuts.escape_key?(params) ->
        BacViewWeb.Shortcuts.apply_escape_close(socket, fn event, sock ->
          handle_event(event, %{}, sock)
        end)

      true ->
        key = Map.get(params, "key", "")
        BacViewWeb.Shortcuts.handle(key, socket, refresh: :scan_network)
    end
  end

  @impl true
  def handle_event("toggle_shortcuts", _params, socket) do
    {:noreply, BacViewWeb.Shortcuts.toggle_shortcuts(socket)}
  end

  @impl true
  def handle_event("toggle_alarm_popup", _params, socket) do
    {:noreply, ActiveAlarmsAssigns.toggle(socket, grouped_alarm_opts(socket))}
  end

  @impl true
  def handle_event("select_alarm_popup_device", %{"device_id" => device_id}, socket) do
    case Integer.parse(device_id) do
      {id, ""} ->
        {:noreply, ActiveAlarmsAssigns.select_device(socket, id, grouped_alarm_opts(socket))}

      _invalid ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_alarm_popup_devices", _params, socket) do
    {:noreply, ActiveAlarmsAssigns.back_to_devices(socket, grouped_alarm_opts(socket))}
  end

  @impl true
  def handle_event("close_alarm_popup", _params, socket) do
    {:noreply, ActiveAlarmsAssigns.close(socket)}
  end

  @impl true
  def handle_event("toggle_cov_popup", _params, socket) do
    {:noreply, ActiveCovSubscriptionsAssigns.toggle(socket, grouped_cov_opts(socket))}
  end

  @impl true
  def handle_event("close_cov_popup", _params, socket) do
    {:noreply, ActiveCovSubscriptionsAssigns.close(socket)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_device_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :device_view, DeviceList.normalize_view(view))}
  end

  @impl true
  def handle_event("clear_devices", _params, socket) do
    :ok = Discovery.cancel_scan()

    {:noreply,
     socket
     |> assign(:devices, [])
     |> assign(:scanning, false)
     |> assign(:last_scan_at, nil)
     |> assign(:device_search, "")
     |> put_flash(:info, gt("Geräteliste geleert."))}
  end

  @impl true
  def handle_event("search_devices", %{"value" => search}, socket) do
    {:noreply, assign(socket, :device_search, search)}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in [
             "toggle_device_services_menu",
             "close_device_services_menu",
             "open_device_service_modal",
             "close_device_service_modal",
             "device_service_form_change",
             "execute_device_service",
             "scan_device"
           ] do
    case DeviceServicesHandlers.handle_event(event, params, socket) do
      {:noreply, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sort_devices", %{"column" => column}, socket) do
    case DeviceList.normalize_sort_column(column) do
      nil ->
        {:noreply, socket}

      column ->
        {sort_by, sort_dir} =
          DeviceList.toggle_sort(
            socket.assigns.device_sort_by,
            socket.assigns.device_sort_dir,
            column
          )

        {:noreply,
         socket
         |> assign(:device_view, :table)
         |> assign(:device_sort_by, sort_by)
         |> assign(:device_sort_dir, sort_dir)}
    end
  end

  @impl true
  def handle_info(:refresh_stack_status, socket) do
    socket =
      socket
      |> refresh_stack_status()
      |> schedule_stack_status_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stack_restart_complete, result}, socket) do
    socket =
      socket
      |> refresh_stack_status()
      |> apply_stack_restart_result(result)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply,
     socket
     |> assign(:devices, devices)
     |> refresh_dashboard_badge_state()}
  end

  @impl true
  def handle_info({:scan_complete, {:ok, devices}}, socket) do
    {:noreply,
     socket
     |> assign(:devices, devices)
     |> assign(:scanning, false)
     |> assign(:last_scan_at, DateTime.utc_now())
     |> DeviceBadgeCounts.assign_counts()
     |> put_flash(:info, gt("Netzwerkscan abgeschlossen."))}
  end

  @impl true
  def handle_info({:scan_complete, {:error, :cancelled}}, socket) do
    {:noreply,
     socket
     |> assign(:devices, [])
     |> assign(:scanning, false)
     |> assign(:last_scan_at, nil)}
  end

  @impl true
  def handle_info({:scan_complete, {:error, :already_scanning}}, socket) do
    {:noreply,
     socket
     |> assign(:scanning, false)
     |> put_flash(:info, gt("Scan läuft bereits."))}
  end

  @impl true
  def handle_info({:scan_complete, {:error, {:bbmd_registration_failed, reason}}}, socket) do
    status = ForeignRegistration.status()

    {:noreply,
     socket
     |> assign(:scanning, false)
     |> assign(:bbmd_status, status)
     |> assign(:bbmd_form, bbmd_form(status))
     |> LiveFlash.put_error(:bbmd_register, reason)}
  end

  @impl true
  def handle_info({:scan_complete, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:scanning, false)
     |> LiveFlash.put_error(:network_scan, reason)}
  end

  @impl true
  def handle_info(:alarms_updated, socket) do
    {:noreply, refresh_dashboard_badge_state(socket)}
  end

  @impl true
  def handle_info(:cov_updated, socket) do
    {:noreply, refresh_dashboard_badge_state(socket)}
  end

  @impl true
  def handle_info(:shortcut_scan, socket) do
    if socket.assigns.scanning do
      {:noreply, socket}
    else
      params = %{"scan" => scan_form_params(socket.assigns.scan_form)}
      handle_event("scan_network", params, socket)
    end
  end

  @impl true
  def handle_info({:device_service_complete, _service, _result} = msg, socket) do
    case DeviceServicesHandlers.handle_info(msg, socket) do
      {:noreply, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:device_scan_complete, _device_id, _result} = msg, socket) do
    case DeviceServicesHandlers.handle_info(msg, socket) do
      {:noreply, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:log_entry, entry}, socket) do
    {:noreply, LogViewerLive.append_entry(socket, entry)}
  end

  def handle_info({:bbmd_updated, status}, socket) do
    {:noreply,
     socket
     |> assign(:bbmd_status, status)
     |> assign(:bbmd_form, bbmd_form(status))}
  end

  def handle_info({:network_number_updated, %{learned: learned}}, socket) do
    {:noreply, assign(socket, :learned_network_number, learned)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      locale={@locale}
      locale_version={@locale_version}
      show_shortcuts={@show_shortcuts}
      shortcuts_context={:dashboard}
    >
      <:topbar_end>
        <%= for _ <- [@locale_version] do %>
          <ActiveAlarmsPopup.active_alarms_badge
            count={DeviceBadgeCounts.total_alarm_count(@device_badge_counts)}
            open={@alarm_popup_open}
            show_device_label={true}
            locale={@locale}
            locale_version={@locale_version}
          />
          <ActiveCovSubscriptionsPopup.active_cov_badge
            count={DeviceBadgeCounts.total_cov_count(@device_badge_counts)}
            open={@cov_popup_open}
            locale={@locale}
            locale_version={@locale_version}
          />
        <% end %>
      </:topbar_end>

      <%= for _ <- [
        {@locale_version, @device_service_menu, @scanning, @bbmd_status, @stack_settings,
         @stack_status, @stack_restart_confirm}
      ] do %>
      <div class="flex flex-1 min-h-0">
        <aside class="bac-sidebar">
          <div class="bac-panel-header">
            <div>
              <p class="bac-section-title">{t(@locale, @locale_version, "Netzwerk")}</p>
              <p class="text-sm bac-text-muted mt-0.5">
                {t(@locale, @locale_version, "Scan & Konfiguration")}
              </p>
            </div>
          </div>

          <div class="bac-sidebar-scroll">
            <ScanPanel.scan_panel
              form={@scan_form}
              scanning={@scanning}
              variant={:sidebar}
              locale={@locale}
              locale_version={@locale_version}
            />

            <div class="bac-divider" />

            <StackSettingsPanel.stack_settings_panel
              form={@stack_form}
              settings={@stack_settings}
              stack_status={@stack_status}
              interface_options={@stack_interface_options}
              confirm_restart?={@stack_restart_confirm and @stack_pending_updates != :manual}
              manual_restart_confirm?={@stack_restart_confirm and @stack_pending_updates == :manual}
              apply_disabled?={@stack_settings.interface_error != nil}
              learned_network_number={@learned_network_number}
              locale={@locale}
              locale_version={@locale_version}
            />

            <div :if={@stack_settings.transport == "ipv4"} class="bac-divider" />

            <BBMDPanel.bbmd_panel
              :if={@stack_settings.transport == "ipv4"}
              status={@bbmd_status}
              form={@bbmd_form}
              locale={@locale}
              locale_version={@locale_version}
            />
          </div>
        </aside>

        <main class="flex-1 flex flex-col min-h-0">
          <header class="bac-page-header">
            <div class="bac-page-header-main">
              <h1 class="bac-page-title">{t(@locale, @locale_version, "BACnet Netzwerk-Explorer")}</h1>
              <p class="bac-page-subtitle">
                {t(@locale, @locale_version, 
                  "Scannen Sie das Netzwerk, wählen Sie ein Gerät und erkunden Sie Objekte und Eigenschaften in Echtzeit."
                )}
              </p>
            </div>
            <p class="bac-page-meta">
              {device_count_label(@devices, @device_search, @vendor_names, @locale, @locale_version)}
            </p>
          </header>

          <div class="bac-page-body">
            <DeviceList.device_list
              devices={@devices}
              vendor_names={@vendor_names}
              scanning={@scanning}
              view={@device_view}
              search={@device_search}
              sort_by={@device_sort_by}
              sort_dir={@device_sort_dir}
              device_service_menu={@device_service_menu}
              device_badge_counts={@device_badge_counts}
              locale={@locale}
              locale_version={@locale_version}
            />
          </div>
        </main>
      </div>

      <Layouts.app_footer locale={@locale} locale_version={@locale_version} />
      <% end %>
    </Layouts.app>

    <ActiveAlarmsPopup.active_alarms_panel
      open={@alarm_popup_open}
      grouped?={@alarm_popup_grouped?}
      level={@alarm_popup_level}
      device_groups={@active_alarm_device_groups}
      selected_device_id={@alarm_popup_device_id}
      entries={@active_alarm_entries}
      show_device={false}
      locale={@locale}
      locale_version={@locale_version}
    />

    <ActiveCovSubscriptionsPopup.active_cov_panel
      open={@cov_popup_open}
      grouped?={@cov_popup_grouped?}
      device_groups={@active_cov_device_groups}
      total_count={DeviceBadgeCounts.total_cov_count(@device_badge_counts)}
      locale={@locale}
      locale_version={@locale_version}
    />

    <LogViewerModal.modal
      open={@log_viewer_open}
      entries={@log_viewer_entries}
      level_filter={@log_viewer_level}
      log_path={@log_path}
      locale={@locale}
      locale_version={@locale_version}
    />

    <%= for _ <- [{@locale_version, @device_service_menu}] do %>
      <DeviceServicesMenu.panel
        menu={@device_service_menu}
        locale={@locale}
        locale_version={@locale_version}
      />
    <% end %>

    <%= for _ <- [{@locale_version, @device_service_modal, @device_service_busy}] do %>
      <DeviceServiceModals.modals
        modal={@device_service_modal}
        busy={@device_service_busy}
        locale={@locale}
        locale_version={@locale_version}
      />
    <% end %>
    """
  end

  defp device_count_label(devices, search, vendor_names, locale, locale_version) do
    _track = locale_version
    Gettext.put_locale(BacViewWeb.Gettext, locale)
    filtered = DeviceList.filtered_devices(devices, search, vendor_names)

    cond do
      devices == [] ->
        gt("0 Geräte")

      search == "" ->
        gt("%{count} Geräte", count: length(devices))

      true ->
        gt("%{shown} von %{total} Geräten", shown: length(filtered), total: length(devices))
    end
  end

  defp refresh_dashboard_badge_state(socket) do
    socket = DeviceBadgeCounts.assign_counts(socket)

    socket
    |> ActiveAlarmsAssigns.refresh(grouped_alarm_opts(socket))
    |> ActiveCovSubscriptionsAssigns.refresh(grouped_cov_opts(socket))
  end

  defp grouped_alarm_opts(socket) do
    [grouped_device_ids: Enum.map(socket.assigns.devices, & &1.id)]
  end

  defp grouped_cov_opts(socket) do
    [
      grouped_devices: socket.assigns.devices,
      device_badge_counts: socket.assigns.device_badge_counts
    ]
  end

  defp scan_form(params \\ %{}) do
    to_form(
      %{
        "timeout_ms" =>
          Map.get(params, "timeout_ms", Integer.to_string(Discovery.default_timeout())),
        "target_ip" => Map.get(params, "target_ip", ""),
        "device_id_low" => Map.get(params, "device_id_low", ""),
        "device_id_high" => Map.get(params, "device_id_high", ""),
        "vendor_id" => Map.get(params, "vendor_id", "")
      },
      as: :scan
    )
  end

  defp scan_form_params(%Phoenix.HTML.Form{} = form) do
    %{
      "timeout_ms" => form[:timeout_ms].value,
      "target_ip" => form[:target_ip].value,
      "device_id_low" => form[:device_id_low].value,
      "device_id_high" => form[:device_id_high].value,
      "vendor_id" => form[:vendor_id].value
    }
  end

  defp sync_discovery_acceptance_filters(%Phoenix.HTML.Form{} = form) do
    case Discovery.parse_scan_params(scan_form_params(form)) do
      {:ok, opts} ->
        Discovery.set_acceptance_filters(opts)

      {:error, _reason} ->
        # Intermediate/invalid form input keeps the last valid filters.
        :ok
    end
  end

  defp bbmd_form(status) do
    to_form(
      %{
        "bbmd_host" => status.bbmd_host || "",
        "bbmd_port" => to_string(status.bbmd_port || 47_808),
        "bbmd_ttl" => to_string(status.ttl || 600)
      },
      as: :bbmd
    )
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _value -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_value, default), do: default

  defp schedule_stack_status_refresh(socket) do
    interval = StackStatusPolling.poll_interval_ms(socket.assigns.stack_status_fast_poll_until)
    Process.send_after(self(), :refresh_stack_status, interval)
    socket
  end

  defp refresh_stack_status(socket) do
    status = Stack.status()

    socket
    |> assign(:stack_status, status)
    |> maybe_end_fast_stack_status_poll(status)
  end

  defp maybe_end_fast_stack_status_poll(socket, status) do
    until = socket.assigns.stack_status_fast_poll_until
    now = System.monotonic_time(:millisecond)

    if StackStatusPolling.end_fast_poll?(until, now, status) do
      assign(socket, :stack_status_fast_poll_until, nil)
    else
      socket
    end
  end

  defp begin_fast_stack_status_poll(socket) do
    Process.send_after(self(), :refresh_stack_status, 0)

    assign(socket, :stack_status_fast_poll_until, StackStatusPolling.begin_fast_poll())
  end

  defp start_stack_restart_async(socket) do
    pid = self()

    Task.start(fn ->
      send(pid, {:stack_restart_complete, StackLifecycle.restart()})
    end)

    socket
  end

  defp apply_stack_restart_result(socket, :ok) do
    socket
    |> assign(:devices, [])
    |> assign(:last_scan_at, nil)
    |> assign(:learned_network_number, learned_network_number())
    |> put_flash(:info, gt("BACnet-Stack neu gestartet."))
  end

  defp apply_stack_restart_result(socket, {:error, reason}) do
    LiveFlash.put_error(socket, :stack_restart, reason)
  end

  defp assign_stack_settings(socket, settings) do
    socket
    |> assign(:stack_settings, settings)
    |> refresh_stack_interfaces(settings.transport, settings.interface)
  end

  defp refresh_stack_interfaces(socket, transport \\ nil, interface \\ nil) do
    form_values =
      case socket.assigns[:stack_form] do
        %Phoenix.HTML.Form{} = form -> stack_form_values(form)
        _socket -> stack_settings_to_form(socket.assigns.stack_settings)
      end

    transport = transport || form_values["transport"] || socket.assigns.stack_settings.transport
    interface = if is_nil(interface), do: form_values["interface"], else: interface

    {resolved, options, error} =
      case InterfaceSelection.resolve(transport, blank_to_nil(interface)) do
        {:ok, %{interface: interface, options: options}} ->
          {interface, options, nil}

        {:error, error, %{options: options, interface: interface}} ->
          {interface, options, error}
      end

    updated_values =
      form_values
      |> Map.put("transport", transport)
      |> Map.put("interface", resolved || "")

    socket
    |> assign(:stack_interface_options, options)
    |> assign(:stack_form, stack_form(updated_values, options))
    |> assign(:stack_settings, %{socket.assigns.stack_settings | interface_error: error})
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp stack_form(params, interface_options) when is_map(params) do
    values = params

    resolved_interface =
      case Enum.find(interface_options, &(&1.value == values["interface"])) do
        %{value: value} -> value
        _params -> interface_options |> List.first() |> then(&if &1, do: &1.value, else: "")
      end

    to_form(
      Map.put(values, "interface", resolved_interface),
      as: :stack
    )
  end

  defp stack_settings_to_form(settings) do
    %{
      "transport" => settings.transport,
      "interface" => settings.interface || "",
      "device_id" => Integer.to_string(settings.device_id),
      "ipv4_port" => Integer.to_string(settings.ipv4_port),
      "network_number" => Integer.to_string(settings.network_number),
      "max_apdu_length" => Integer.to_string(settings.max_apdu_length),
      "cov_lifetime_seconds" => Integer.to_string(settings.cov_lifetime_seconds),
      "cov_increment" => cov_increment_form_value(settings.cov_increment),
      "cov_confirmed" => if(settings.cov_confirmed, do: "true", else: "false"),
      "scan_on_online" => if(settings.scan_on_online, do: "true", else: "false"),
      "mstp_local_address" => Integer.to_string(settings.mstp_local_address),
      "mstp_baud_rate" => mstp_baud_rate_form_value(settings.mstp_baud_rate)
    }
  end

  defp stack_form_values(%Phoenix.HTML.Form{} = form) do
    %{
      "transport" => form[:transport].value,
      "interface" => form[:interface].value,
      "device_id" => form[:device_id].value,
      "ipv4_port" => form[:ipv4_port].value,
      "network_number" => form[:network_number].value,
      "max_apdu_length" => form[:max_apdu_length].value,
      "cov_lifetime_seconds" => form[:cov_lifetime_seconds].value,
      "cov_increment" => form[:cov_increment].value,
      "cov_confirmed" => form[:cov_confirmed].value,
      "scan_on_online" => form[:scan_on_online].value,
      "mstp_local_address" => form[:mstp_local_address].value,
      "mstp_baud_rate" => form[:mstp_baud_rate].value
    }
  end

  defp parse_stack_updates(params, current_settings) do
    transport = params["transport"] || current_settings.transport || "ipv4"

    # MS/TP fields are not rendered for BACnet/IP; keep persisted values when absent.
    mstp_local_address_param =
      params["mstp_local_address"] || Integer.to_string(current_settings.mstp_local_address)

    mstp_baud_rate_param =
      params["mstp_baud_rate"] || mstp_baud_rate_form_value(current_settings.mstp_baud_rate)

    ipv4_port_param =
      params["ipv4_port"] || Integer.to_string(current_settings.ipv4_port)

    max_apdu_param =
      params["max_apdu_length"] || Integer.to_string(current_settings.max_apdu_length)

    with {:ok, device_id} <- parse_required_int(params["device_id"], 0, 4_194_303),
         {:ok, ipv4_port} <- parse_required_int(ipv4_port_param, 47_808, 65_535),
         {:ok, network_number} <- parse_required_int(params["network_number"], 0, 65_534),
         {:ok, max_apdu_length} <- parse_required_int(max_apdu_param, 50, 1476),
         {:ok, cov_lifetime} <- parse_required_int(params["cov_lifetime_seconds"], 0, 864_000),
         {:ok, cov_increment} <- parse_cov_increment(params["cov_increment"]),
         {:ok, mstp_local_address} <-
           parse_required_int(mstp_local_address_param, 0, 127),
         {:ok, mstp_baud_rate} <- parse_mstp_baud_rate(mstp_baud_rate_param),
         {:ok, interface} <- resolve_interface(transport, params["interface"]) do
      {:ok,
       [
         transport: transport,
         interface: interface,
         ipv4_port: ipv4_port,
         device_id: device_id,
         network_number: network_number,
         max_apdu_length: max_apdu_length,
         cov_lifetime_seconds: cov_lifetime,
         cov_increment: cov_increment,
         cov_confirmed: form_checkbox?(params["cov_confirmed"]),
         scan_on_online: form_checkbox?(params["scan_on_online"]),
         mstp_local_address: mstp_local_address,
         mstp_baud_rate: mstp_baud_rate
       ]}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp learned_network_number() do
    NetworkNumber.learned()
  end

  defp form_checkbox?(value) when value in [true, "true", "on"], do: true
  defp form_checkbox?(["false", "true"]), do: true
  defp form_checkbox?(_value), do: false

  defp cov_increment_form_value(nil), do: ""

  defp cov_increment_form_value(value) when is_number(value),
    do: PropertyFormatter.format_float(value * 1.0)

  defp parse_cov_increment(nil), do: {:ok, nil}
  defp parse_cov_increment(""), do: {:ok, nil}

  defp parse_cov_increment(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      case Float.parse(trimmed) do
        {float, ""} when float >= 0 -> {:ok, float * 1.0}
        _value -> {:error, :invalid_settings}
      end
    end
  end

  defp parse_cov_increment(value) when is_number(value) and value >= 0, do: {:ok, value * 1.0}
  defp parse_cov_increment(_value), do: {:error, :invalid_settings}

  defp parse_required_int(value, min, max) do
    case Integer.parse(to_string(value || "")) do
      {int, ""} when int >= min and int <= max -> {:ok, int}
      _value -> {:error, :invalid_settings}
    end
  end

  defp mstp_baud_rate_form_value(:auto), do: "auto"
  defp mstp_baud_rate_form_value(rate) when is_integer(rate), do: Integer.to_string(rate)

  defp parse_mstp_baud_rate("auto"), do: {:ok, :auto}

  defp parse_mstp_baud_rate(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int in [9600, 19_200, 38_400, 57_600, 76_800, 115_200] ->
        {:ok, int}

      _value ->
        {:error, :invalid_settings}
    end
  end

  defp parse_mstp_baud_rate(_value), do: {:error, :invalid_settings}

  defp resolve_interface(transport, interface) do
    options = Settings.interface_options(transport)
    trimmed = interface |> to_string() |> String.trim()

    cond do
      trimmed == "" ->
        {:error, :no_interface}

      trimmed in Enum.map(options, & &1.value) ->
        {:ok, trimmed}

      true ->
        case options do
          [%{value: fallback} | _rest] -> {:ok, fallback}
          [] -> {:error, :no_interface}
        end
    end
  end

  defp preview_settings(current, updates) do
    Enum.reduce(updates, current, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end

  defp save_stack_settings(socket, updates, opts \\ []) do
    restart? =
      Keyword.get(opts, :restart?, false) or
        StackStatusPolling.stack_offline?(socket.assigns.stack_status)

    case Settings.update(updates) do
      {:ok, settings} ->
        NetworkNumber.reload_from_settings()

        socket =
          socket
          |> assign_stack_settings(settings)
          |> assign(:stack_status, Stack.status())
          |> assign(:learned_network_number, learned_network_number())
          |> put_flash(:info, gt("Stack-Einstellungen gespeichert."))

        socket =
          if restart? do
            assign(socket, :scanning, false)
          else
            socket
          end

        if restart? do
          socket
          |> begin_fast_stack_status_poll()
          |> start_stack_restart_async()
        else
          socket
        end

      {:error, reason} ->
        put_flash(socket, :error, stack_settings_error(reason))
    end
  end

  defp stack_settings_error(:invalid_settings),
    do: gt("Ungültige Stack-Einstellungen.")

  defp stack_settings_error(:invalid_transport),
    do: gt("Unbekannter Transport.")

  defp stack_settings_error(:invalid_interface),
    do: gt("Schnittstelle ist erforderlich.")

  defp stack_settings_error(:no_interface),
    do: gt("Bitte eine Schnittstelle auswählen.")

  defp stack_settings_error(_invalid_settings),
    do: gt("Stack-Einstellungen konnten nicht gespeichert werden.")
end
