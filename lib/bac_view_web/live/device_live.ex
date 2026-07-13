defmodule BacViewWeb.DeviceLive do
  @moduledoc false
  use BacViewWeb, :live_view

  alias BACnet.Protocol.ObjectIdentifier

  alias BacView.BACnet.Address
  alias BacView.BACnet.AlarmEvent
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.HierarchyBuilder
  alias BacView.BACnet.HierarchySplit
  alias BacView.BACnet.NameHierarchyBuilder
  alias BacView.BACnet.NameHierarchyCache
  alias BacView.BACnet.NotificationClassRecipient
  alias BacView.BACnet.SubscriptionManager

  alias BacView.BACnet.Protocol.CovNotificationChart
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.PropertyWriter
  alias BacView.BACnet.Protocol.StatusFlagsParser
  alias BacView.BACnet.Protocol.TrendLogChart
  alias BacView.BACnet.Protocol.TrendLogExport

  alias BacViewWeb.ActiveAlarmsAssigns
  alias BacViewWeb.ActiveAlarmsPopup
  alias BacViewWeb.AlarmsPanel
  alias BacViewWeb.CovNotificationChartModal
  alias BacViewWeb.DeviceLoadProgress
  alias BacViewWeb.DeviceScanRecovery
  alias BacViewWeb.DeviceServiceModals
  alias BacViewWeb.DeviceServicesHandlers
  alias BacViewWeb.DeviceServicesMenu
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.HierarchyExplorer
  alias BacViewWeb.HierarchyPanel
  alias BacViewWeb.LiveFlash
  alias BacViewWeb.ObjectSelectionBar
  alias BacViewWeb.ObjectTable
  alias BacViewWeb.ObjectTypeIcon
  alias BacViewWeb.StatusFlagsIcons
  alias BacViewWeb.SubscriptionSelectionBar
  alias BacViewWeb.SubscriptionsPanel
  alias BacViewWeb.WritePresentValueModal

  @valid_tabs ~w(hierarchy objects subscriptions alarms)
  @default_tab "hierarchy"

  @impl true
  def mount(%{"device_id" => device_id_str}, _session, socket) do
    device_id = String.to_integer(device_id_str)

    case Discovery.get_device(device_id) do
      {:ok, device} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(BacView.PubSub, "device:#{device_id}:cov")
          Phoenix.PubSub.subscribe(BacView.PubSub, "device:#{device_id}:alarms")
          Phoenix.PubSub.subscribe(BacView.PubSub, "device:#{device_id}:load_progress")
          Phoenix.PubSub.subscribe(BacView.PubSub, "cov:updates")
          send(self(), {:load_device, false})
        end

        {:ok,
         socket
         |> assign(:page_title, device.name || "Device #{device_id}")
         |> assign(:device, device)
         |> assign(:device_id, device_id)
         |> assign(:tab, @default_tab)
         |> assign(:objects, [])
         |> assign(:hierarchy, empty_hierarchy())
         |> assign(:sv_hierarchy, empty_hierarchy())
         |> assign(:hierarchy_split, nil)
         |> assign(:hierarchy_source, :structured)
         |> assign(:name_hierarchy_form_open, false)
         |> assign(:tree_roots, [])
         |> assign(:tree_match_count, 0)
         |> assign(:tree_search, "")
         |> assign(:explorer_search, "")
         |> assign(:explorer_match_count, 0)
         |> assign(:tree_expanded, MapSet.new())
         |> assign(:hierarchy_view, "explorer")
         |> assign(:hierarchy_path, [])
         |> assign(:hierarchy_entries, [])
         |> assign(:hierarchy_path_links, [])
         |> assign(:hierarchy_root_path, "")
         |> assign(:loading, true)
         |> assign(:loading_in_progress, false)
         |> assign(:load_progress, %{stage: :connecting, done: 0, total: nil})
         |> assign(:scan_retrying, %{})
         |> assign(:search, "")
         |> assign(:type_filter, [])
         |> assign(:type_filter_open, false)
         |> assign(:status_filter, [])
         |> assign(:status_filter_open, false)
         |> assign(:sort_by, nil)
         |> assign(:sort_dir, :asc)
         |> assign(:subscriptions, [])
         |> assign(:cov_notifications, [])
         |> assign(:cov_view, "subscriptions")
         |> assign(:subscribed_keys, MapSet.new())
         |> assign(:flash_cells, MapSet.new())
         |> assign(:cov_count, 0)
         |> assign(:bulk_subscribing, false)
         |> assign(:bulk_progress, %{done: 0, total: 0})
         |> assign(:alarm_view, "event_information")
         |> assign(:events, [])
         |> assign(:notifications, [])
         |> assign(:active_alarm_objects, [])
         |> assign(:alarm_tab_count, 0)
         |> assign(:alarm_summary, %{
           active_count: 0,
           unacknowledged_count: 0,
           highest_priority: nil
         })
         |> assign(:alarms_refreshing, false)
         |> assign(:nc_subscribing, false)
         |> assign(:nc_progress, %{done: 0, total: 0})
         |> assign(:nc_enrolled_count, 0)
         |> assign(:nc_total, 0)
         |> assign(:alarm_events_sort_by, nil)
         |> assign(:alarm_events_sort_dir, :asc)
         |> assign(:active_alarms_sort_by, nil)
         |> assign(:active_alarms_sort_dir, :asc)
         |> assign(:alarm_notifications_sort_by, nil)
         |> assign(:alarm_notifications_sort_dir, :asc)
         |> assign(:subscriptions_sort_by, nil)
         |> assign(:subscriptions_sort_dir, :asc)
         |> assign(:cov_notifications_sort_by, BacViewWeb.CovNotificationTable.default_sort_by())
         |> assign(
           :cov_notifications_sort_dir,
           BacViewWeb.CovNotificationTable.default_sort_dir()
         )
         |> assign(:flash_alarm_rows, MapSet.new())
         |> assign(:selected_object_keys, MapSet.new())
         |> assign(:selected_subscription_keys, MapSet.new())
         |> assign(:selectable_object_keys, MapSet.new())
         |> assign(:cov_chart_modal_open, false)
         |> assign(:cov_chart_loading, false)
         |> assign(:cov_chart_error, nil)
         |> assign(:cov_chart_start, "")
         |> assign(:cov_chart_end, "")
         |> assign(:cov_chart_data, nil)
         |> assign(:cov_chart_has_data, false)
         |> assign(:cov_chart_record_count, 0)
         |> assign(:cov_chart_subscription, nil)
         |> assign(:cov_chart_object, nil)
         |> assign(:write_modal, nil)
         |> assign(:write_priority, PropertyWriter.default_priority())
         |> assign(:writing_present_value, false)
         |> assign(:show_shortcuts, false)
         |> DeviceServicesHandlers.init_assigns()
         |> ActiveAlarmsAssigns.init()
         |> refresh_alarm_state()
         |> refresh_notification_class_counts()}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, gt("Gerät nicht gefunden."))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:tab, normalize_tab(Map.get(params, "tab")))
     |> assign(:search, DeviceUrl.normalize_search(Map.get(params, "search")))
     |> assign(:type_filter, DeviceUrl.normalize_types(Map.get(params, "types")))
     |> assign(:type_filter_open, false)
     |> assign(:status_filter, DeviceUrl.normalize_status(Map.get(params, "status")))
     |> assign(:status_filter_open, false)
     |> assign(:sort_by, DeviceUrl.normalize_sort_column(Map.get(params, "sort")))
     |> assign(:sort_dir, DeviceUrl.normalize_sort_dir(Map.get(params, "dir")))
     |> assign(:alarm_view, DeviceUrl.normalize_alarm_view(Map.get(params, "alarm_view")))
     |> assign(:cov_view, DeviceUrl.normalize_cov_view(Map.get(params, "cov_view")))
     |> assign(
       :hierarchy_view,
       DeviceUrl.normalize_hierarchy_view(Map.get(params, "hierarchy_view"))
     )
     |> assign(:hierarchy_path, DeviceUrl.normalize_hierarchy_path(Map.get(params, "h_path")))
     |> assign(:hierarchy_split, resolve_hierarchy_split(socket, params))
     |> apply_active_hierarchy()}
  end

  @impl true
  def handle_info({:load_device, force?}, socket) when is_boolean(force?) do
    if socket.assigns.loading_in_progress and not force? do
      {:noreply, socket}
    else
      parent = self()
      device_id = socket.assigns.device_id

      Task.start(fn ->
        result =
          try do
            if force? do
              DeviceSession.reload(device_id)
            else
              DeviceSession.load(device_id)
            end
          rescue
            exception -> {:error, exception}
          catch
            :exit, reason -> {:error, reason}
          end

        send(parent, {:device_load_done, result})
      end)

      {:noreply,
       socket
       |> assign(:loading, true)
       |> assign(:loading_in_progress, true)
       |> assign(:load_progress, %{stage: :connecting, done: 0, total: nil})}
    end
  end

  @impl true
  def handle_info({:device_load_done, result}, socket) do
    socket = assign(socket, :loading_in_progress, false)

    case result do
      {:ok, loaded} ->
        {:noreply, apply_loaded_device(socket, loaded)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:load_progress, nil)
         |> LiveFlash.put_error(:load_device, reason)}
    end
  end

  @impl true
  def handle_info({:device_load_progress, progress}, socket) do
    {:noreply, assign(socket, :load_progress, progress)}
  end

  @impl true
  def handle_info({:write_modal_priority, type, instance, priority_array}, socket) do
    {:noreply, apply_write_modal_priority(socket, type, instance, priority_array)}
  end

  @impl true
  def handle_info({:device_service_complete, _service, _result} = msg, socket) do
    case DeviceServicesHandlers.handle_info(msg, socket) do
      {:noreply, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:cov_update, update}, socket) do
    socket =
      case update.property do
        :present_value ->
          objects =
            Enum.map(socket.assigns.objects, fn obj ->
              if obj.type == update.type and obj.instance == update.instance do
                Map.merge(obj, %{
                  present_value: PropertyFormatter.coerce_present_value(update.value, obj),
                  present_value_formatted:
                    PropertyFormatter.format_present_value(update.value, obj),
                  updated_at: update.at
                })
              else
                obj
              end
            end)

          flash_cells = MapSet.put(socket.assigns.flash_cells, {update.type, update.instance})

          socket
          |> assign(:objects, objects)
          |> assign(:flash_cells, flash_cells)
          |> refresh_hierarchy_explorer()

        :status_flags ->
          objects =
            Enum.map(socket.assigns.objects, fn obj ->
              if obj.type == update.type and obj.instance == update.instance do
                Map.merge(obj, %{
                  status_flags: StatusFlagsParser.normalize(update.value),
                  updated_at: update.at
                })
              else
                obj
              end
            end)

          socket
          |> assign(:objects, objects)
          |> refresh_hierarchy_explorer()

        _property ->
          socket
      end

    {:noreply,
     socket
     |> refresh_cov_state()
     |> refresh_cov_notifications()
     |> refresh_active_alarm_objects()
     |> refresh_alarm_popup()}
  end

  @impl true
  def handle_info({:cov_notification, _entry}, socket) do
    socket = refresh_cov_notifications(socket)

    socket =
      if socket.assigns.cov_chart_modal_open do
        send(self(), :load_cov_chart)
        assign(socket, :cov_chart_loading, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_cov_chart, socket) do
    if socket.assigns.cov_chart_modal_open and socket.assigns.cov_chart_subscription do
      parent = self()

      payload = %{
        device_id: socket.assigns.device_id,
        subscription: socket.assigns.cov_chart_subscription,
        notifications: socket.assigns.cov_notifications,
        objects: socket.assigns.objects,
        start_value: socket.assigns.cov_chart_start,
        end_value: socket.assigns.cov_chart_end
      }

      Task.start(fn ->
        result = load_cov_chart_data(payload)
        send(parent, {:cov_chart_loaded, result})
      end)

      {:noreply, assign(socket, :cov_chart_loading, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:cov_chart_loaded, result}, socket) do
    socket = assign(socket, :cov_chart_loading, false)

    case result do
      {:ok,
       %{
         data: data,
         records: records,
         start_dt: start_dt,
         end_dt: end_dt
       }} ->
        {:noreply,
         socket
         |> assign(:cov_chart_data, data)
         |> assign(:cov_chart_start, TrendLogChart.to_form_value(start_dt))
         |> assign(:cov_chart_end, TrendLogChart.to_form_value(end_dt))
         |> assign(:cov_chart_has_data, chart_has_data?(data))
         |> assign(:cov_chart_record_count, length(records))
         |> assign(:cov_chart_error, nil)
         |> push_event("trend-chart:update", chart_event_payload(data))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:cov_chart_data, nil)
         |> assign(:cov_chart_has_data, false)
         |> assign(:cov_chart_record_count, 0)
         |> assign(:cov_chart_error, ErrorMessage.format_reason(reason))
         |> push_event("trend-chart:update", %{series: [], scales: [], empty_label: nil})}
    end
  end

  @impl true
  def handle_info(:cov_updated, socket) do
    {:noreply, socket |> refresh_cov_state() |> refresh_cov_notifications()}
  end

  @impl true
  def handle_info({:cov_bulk_progress, done, total}, socket) do
    {:noreply,
     socket
     |> assign(:bulk_subscribing, true)
     |> assign(:bulk_progress, %{done: done, total: total})}
  end

  @impl true
  def handle_info(:alarms_updated, socket) do
    {:noreply, refresh_alarm_popup(refresh_alarm_state(socket))}
  end

  @impl true
  def handle_info({:alarm_update, update}, socket) do
    flash_rows =
      MapSet.put(
        socket.assigns.flash_alarm_rows,
        {update.object_id.type, update.object_id.instance}
      )

    {:noreply,
     socket
     |> assign(:flash_alarm_rows, flash_rows)
     |> refresh_alarm_state()
     |> refresh_alarm_popup()
     |> put_flash(:info, gt("Neues Ereignis: %{object}", object: object_label(update)))}
  end

  @impl true
  def handle_info({:cov_bulk_done, _total}, socket) do
    {:noreply,
     socket
     |> assign(:bulk_subscribing, false)
     |> assign(:bulk_progress, %{done: 0, total: 0})
     |> refresh_cov_state()
     |> put_flash(:info, gt("Bulk-Abonnement abgeschlossen."))}
  end

  @impl true
  def handle_info({:nc_sync_done, result}, socket) when is_map(result) do
    {:noreply,
     socket
     |> assign(:nc_enrolled_count, Map.get(result, :enrolled, 0))
     |> assign(:nc_total, Map.get(result, :total, 0))}
  end

  @impl true
  def handle_info({:nc_bulk_progress, done, total}, socket) do
    {:noreply,
     socket
     |> assign(:nc_subscribing, true)
     |> assign(:nc_progress, %{done: done, total: total})}
  end

  @impl true
  def handle_info({:nc_bulk_done, result}, socket) when is_map(result) do
    enrolled = Map.get(result, :enrolled, 0)
    total = Map.get(result, :total, 0)
    action = Map.get(result, :action, :subscribe)

    socket =
      socket
      |> assign(:nc_subscribing, false)
      |> assign(:nc_progress, %{done: 0, total: 0})
      |> assign(:nc_enrolled_count, enrolled)
      |> assign(:nc_total, total)
      |> refresh_active_alarm_objects()
      |> nc_bulk_flash(action, enrolled, total)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:shortcut_refresh_device, socket) do
    {:noreply, start_device_reload(socket)}
  end

  @impl true
  def handle_event("retry_scan_object", params, socket) do
    with {:ok, type_atom} <- parse_type(params["type"]),
         instance_int <- String.to_integer(params["instance"]),
         {:ok, skip_mode} <- parse_skip_mode(params["skip_mode"]),
         object_id <- %ObjectIdentifier{type: type_atom, instance: instance_int} do
      retry_key = "#{type_atom}:#{instance_int}"

      socket =
        assign(socket, :scan_retrying, Map.put(socket.assigns.scan_retrying, retry_key, true))

      case DeviceSession.retry_scan_object(socket.assigns.device_id, object_id, skip_mode) do
        {:ok, _summary} ->
          {:ok, loaded} = DeviceSession.load(socket.assigns.device_id)

          {:noreply,
           socket
           |> assign(:scan_retrying, Map.delete(socket.assigns.scan_retrying, retry_key))
           |> apply_loaded_device(loaded)
           |> put_flash(
             :info,
             gt("Objekt %{object} erfolgreich nachgelesen.",
               object: "#{type_atom}:#{instance_int}"
             )
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:scan_retrying, Map.delete(socket.assigns.scan_retrying, retry_key))
           |> LiveFlash.put_error(:load_properties, reason)}
      end
    else
      _err -> {:noreply, put_flash(socket, :error, gt("Ungültige Objekt-ID."))}
    end
  end

  @impl true
  def handle_event("search_objects", %{"value" => search}, socket) do
    {:noreply, patch_objects_tab(socket, search: search)}
  end

  @impl true
  def handle_event("toggle_type_filter_panel", _params, socket) do
    open? = !socket.assigns.type_filter_open

    {:noreply,
     socket
     |> assign(:type_filter_open, open?)
     |> assign(:status_filter_open, if(open?, do: false, else: socket.assigns.status_filter_open))}
  end

  @impl true
  def handle_event("close_type_filter_panel", _params, socket) do
    {:noreply, assign(socket, :type_filter_open, false)}
  end

  @impl true
  def handle_event("toggle_object_type", %{"type" => type}, socket) do
    case parse_type(type) do
      {:ok, type_atom} ->
        available = ObjectTable.available_types(socket.assigns.objects)

        new_filter =
          ObjectTable.toggle_type_filter(socket.assigns.type_filter, available, type_atom)

        {:noreply, patch_objects_tab(socket, type_filter: new_filter, type_filter_open: true)}

      _err ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_object_type_only", %{"type" => type}, socket) do
    case parse_type(type) do
      {:ok, type_atom} ->
        {:noreply,
         patch_objects_tab(socket,
           type_filter: ObjectTable.filter_type_only(type_atom),
           type_filter_open: false
         )}

      _err ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset_object_type_filter", _params, socket) do
    {:noreply, patch_objects_tab(socket, type_filter: [], type_filter_open: true)}
  end

  @impl true
  def handle_event("toggle_status_filter_panel", _params, socket) do
    open? = !socket.assigns.status_filter_open

    {:noreply,
     socket
     |> assign(:status_filter_open, open?)
     |> assign(:type_filter_open, if(open?, do: false, else: socket.assigns.type_filter_open))}
  end

  @impl true
  def handle_event("close_status_filter_panel", _params, socket) do
    {:noreply, assign(socket, :status_filter_open, false)}
  end

  @impl true
  def handle_event("toggle_object_status", %{"status" => status}, socket) do
    case parse_status(status) do
      {:ok, flag} ->
        available = ObjectTable.available_status_flags(socket.assigns.objects)

        new_filter =
          ObjectTable.toggle_status_filter(socket.assigns.status_filter, available, flag)

        {:noreply, patch_objects_tab(socket, status_filter: new_filter, status_filter_open: true)}

      _err ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_object_status_only", %{"status" => status}, socket) do
    case parse_status(status) do
      {:ok, flag} ->
        {:noreply,
         patch_objects_tab(socket,
           status_filter: ObjectTable.filter_status_only(flag),
           status_filter_open: false
         )}

      _err ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset_object_status_filter", _params, socket) do
    {:noreply, patch_objects_tab(socket, status_filter: [], status_filter_open: true)}
  end

  @impl true
  def handle_event("sort_objects", %{"column" => column}, socket) do
    case ObjectTable.normalize_sort_column(column) do
      nil ->
        {:noreply, socket}

      column ->
        {sort_by, sort_dir} =
          ObjectTable.toggle_sort(socket.assigns.sort_by, socket.assigns.sort_dir, column)

        {:noreply, patch_objects_tab(socket, sort_by: sort_by, sort_dir: sort_dir)}
    end
  end

  @impl true
  def handle_event("sort_alarm_events", %{"column" => column}, socket) do
    {:noreply,
     update_alarm_table_sort(
       socket,
       :alarm_events_sort_by,
       :alarm_events_sort_dir,
       column,
       &BacViewWeb.AlarmTable.normalize_event_sort_column/1
     )}
  end

  @impl true
  def handle_event("sort_active_alarms", %{"column" => column}, socket) do
    {:noreply,
     update_alarm_table_sort(
       socket,
       :active_alarms_sort_by,
       :active_alarms_sort_dir,
       column,
       &BacViewWeb.AlarmTable.normalize_active_alarm_sort_column/1
     )}
  end

  @impl true
  def handle_event("sort_alarm_notifications", %{"column" => column}, socket) do
    {:noreply,
     update_alarm_table_sort(
       socket,
       :alarm_notifications_sort_by,
       :alarm_notifications_sort_dir,
       column,
       &BacViewWeb.AlarmTable.normalize_notification_sort_column/1
     )}
  end

  @impl true
  def handle_event("sort_cov_notifications", %{"column" => column}, socket) do
    case BacViewWeb.CovNotificationTable.normalize_sort_column(column) do
      nil ->
        {:noreply, socket}

      column ->
        {sort_by, sort_dir} =
          BacViewWeb.CovNotificationTable.toggle_sort(
            socket.assigns.cov_notifications_sort_by,
            socket.assigns.cov_notifications_sort_dir,
            column
          )

        {:noreply,
         socket
         |> assign(:cov_notifications_sort_by, sort_by)
         |> assign(:cov_notifications_sort_dir, sort_dir)}
    end
  end

  @impl true
  def handle_event("sort_subscriptions", %{"column" => column}, socket) do
    case BacViewWeb.SubscriptionTable.normalize_sort_column(column) do
      nil ->
        {:noreply, socket}

      column ->
        {sort_by, sort_dir} =
          BacViewWeb.SubscriptionTable.toggle_sort(
            socket.assigns.subscriptions_sort_by,
            socket.assigns.subscriptions_sort_dir,
            column
          )

        {:noreply,
         socket
         |> assign(:subscriptions_sort_by, sort_by)
         |> assign(:subscriptions_sort_dir, sort_dir)}
    end
  end

  @impl true
  def handle_event("search_tree", %{"value" => search}, socket) do
    {roots, count} = HierarchyBuilder.filter_tree(socket.assigns.hierarchy.roots, search)

    {:noreply,
     socket
     |> assign(:tree_search, search)
     |> assign(:tree_roots, roots)
     |> assign(:tree_match_count, count)
     |> assign(:tree_expanded, expand_all(roots))}
  end

  @impl true
  def handle_event("search_hierarchy_explorer", %{"value" => search}, socket) do
    {:noreply,
     socket
     |> assign(:explorer_search, search)
     |> refresh_hierarchy_explorer()}
  end

  @impl true
  def handle_event("build_name_hierarchy", %{"name_hierarchy" => params}, socket) do
    case HierarchySplit.parse_form(params) do
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gt("Ungültige Aufteilungsregeln für die Objektnamen-Hierarchie.")
         )}

      split ->
        NameHierarchyCache.put(socket.assigns.device_id, split, socket.assigns.objects)

        path =
          DeviceUrl.device_path(
            socket.assigns.device_id,
            name_hierarchy_device_opts(socket, split)
          )

        {:noreply,
         socket
         |> assign(:hierarchy_path, [])
         |> assign(:name_hierarchy_form_open, false)
         |> push_patch(to: path)}
    end
  end

  @impl true
  def handle_event("clear_name_hierarchy", _params, socket) do
    NameHierarchyCache.clear(socket.assigns.device_id)

    path =
      DeviceUrl.device_path(
        socket.assigns.device_id,
        name_hierarchy_device_opts(socket, nil)
      )

    {:noreply,
     socket
     |> assign(:hierarchy_path, [])
     |> assign(:name_hierarchy_form_open, false)
     |> push_patch(to: path)}
  end

  @impl true
  def handle_event("toggle_name_hierarchy_form", _params, socket) do
    {:noreply,
     assign(socket, :name_hierarchy_form_open, !socket.assigns.name_hierarchy_form_open)}
  end

  @impl true
  def handle_event("toggle_tree_node", %{"id" => node_id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.tree_expanded, node_id) do
        MapSet.delete(socket.assigns.tree_expanded, node_id)
      else
        MapSet.put(socket.assigns.tree_expanded, node_id)
      end

    {:noreply, assign(socket, :tree_expanded, expanded)}
  end

  @impl true
  def handle_event("subscribe_cov", params, socket) do
    with {:ok, type_atom} <- parse_type(params["type"]),
         instance_int <- String.to_integer(params["instance"]),
         {:ok, property} <- parse_property(params["property"] || "present_value") do
      object_id = %ObjectIdentifier{type: type_atom, instance: instance_int}

      case SubscriptionManager.subscribe(socket.assigns.device_id, object_id, property) do
        :ok ->
          {:noreply,
           socket
           |> refresh_cov_state()
           |> put_flash(:info, gt("COV abonnieren erfolgreich."))}

        {:error, reason} ->
          {:noreply, LiveFlash.put_error(socket, :cov_subscribe, reason)}
      end
    else
      _err -> {:noreply, put_flash(socket, :error, gt("Ungültige Objekt-ID."))}
    end
  end

  @impl true
  def handle_event("unsubscribe_cov", params, socket) do
    with {:ok, type_atom} <- parse_type(params["type"]),
         instance_int <- String.to_integer(params["instance"]),
         {:ok, property} <- parse_property(params["property"] || "present_value") do
      object_id = %ObjectIdentifier{type: type_atom, instance: instance_int}

      case SubscriptionManager.unsubscribe(socket.assigns.device_id, object_id, property) do
        :ok ->
          {:noreply,
           socket
           |> refresh_cov_state()
           |> put_flash(:info, gt("Abonnement kündigen erfolgreich."))}

        {:error, reason} ->
          {:noreply, LiveFlash.put_error(socket, :cov_unsubscribe, reason)}
      end
    else
      _err -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_cov_chart_modal", params, socket) do
    with {:ok, type_atom} <- parse_type(params["type"]),
         instance_int <- String.to_integer(params["instance"]),
         {:ok, property} <- parse_property(params["property"] || "present_value") do
      object_id = %ObjectIdentifier{type: type_atom, instance: instance_int}

      subscription =
        Enum.find(socket.assigns.subscriptions, fn sub ->
          sub.object_id.type == type_atom and sub.object_id.instance == instance_int and
            sub.property == property
        end) || %{object_id: object_id, property: property}

      socket =
        socket
        |> assign(:cov_chart_modal_open, true)
        |> assign(:cov_chart_loading, true)
        |> assign(:cov_chart_error, nil)
        |> assign(:cov_chart_start, "")
        |> assign(:cov_chart_end, "")
        |> assign(:cov_chart_data, nil)
        |> assign(:cov_chart_has_data, false)
        |> assign(:cov_chart_record_count, 0)
        |> assign(:cov_chart_subscription, subscription)
        |> assign(:cov_chart_object, find_chart_object(socket.assigns.objects, object_id))

      send(self(), :load_cov_chart)
      {:noreply, socket}
    else
      _err -> {:noreply, socket}
    end
  end

  def handle_event("close_cov_chart_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:cov_chart_modal_open, false)
     |> assign(:cov_chart_loading, false)
     |> assign(:cov_chart_subscription, nil)
     |> assign(:cov_chart_object, nil)
     |> push_event("trend-chart:update", %{series: [], scales: [], empty_label: nil})}
  end

  def handle_event("cov_chart_change_range", params, socket) do
    {:noreply,
     socket
     |> assign(:cov_chart_start, Map.get(params, "start", socket.assigns.cov_chart_start))
     |> assign(:cov_chart_end, Map.get(params, "end", socket.assigns.cov_chart_end))}
  end

  def handle_event("cov_chart_load", params, socket) do
    socket =
      socket
      |> assign(:cov_chart_start, Map.get(params, "start", socket.assigns.cov_chart_start))
      |> assign(:cov_chart_end, Map.get(params, "end", socket.assigns.cov_chart_end))

    send(self(), :load_cov_chart)
    {:noreply, assign(socket, :cov_chart_loading, true)}
  end

  def handle_event("cov_chart_export_csv", _params, socket) do
    {:noreply, cov_chart_download(socket, :csv)}
  end

  def handle_event("cov_chart_export_json", _params, socket) do
    {:noreply, cov_chart_download(socket, :json)}
  end

  @impl true
  def handle_event("subscribe_all_pv", _params, socket) do
    SubscriptionManager.subscribe_all_present_values(socket.assigns.device_id, self())

    {:noreply,
     socket
     |> assign(:bulk_subscribing, true)
     |> assign(:bulk_progress, %{done: 0, total: 0})}
  end

  @impl true
  def handle_event("toggle_object_selection", %{"type" => type, "instance" => instance}, socket) do
    with {:ok, type_atom} <- parse_type(type),
         {instance_int, ""} <- Integer.parse(instance) do
      keys = object_selection_keys(socket, type_atom, instance_int)

      selected =
        if selection_group_selected?(socket.assigns.selected_object_keys, keys) do
          MapSet.difference(socket.assigns.selected_object_keys, keys)
        else
          MapSet.union(socket.assigns.selected_object_keys, keys)
        end

      {:noreply, assign(socket, :selected_object_keys, selected)}
    else
      _err -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_select_all_hierarchy", _params, socket) do
    visible_keys = hierarchy_visible_selection_keys(socket)

    selected =
      if selection_group_selected?(socket.assigns.selected_object_keys, visible_keys) do
        MapSet.difference(socket.assigns.selected_object_keys, visible_keys)
      else
        MapSet.union(socket.assigns.selected_object_keys, visible_keys)
      end

    {:noreply, assign(socket, :selected_object_keys, selected)}
  end

  @impl true
  def handle_event("toggle_select_all_objects", _params, socket) do
    filtered_keys = filtered_object_keys(socket)

    all_selected? =
      filtered_keys != MapSet.new() and
        MapSet.subset?(filtered_keys, socket.assigns.selected_object_keys)

    selected =
      if all_selected? do
        MapSet.difference(socket.assigns.selected_object_keys, filtered_keys)
      else
        MapSet.union(socket.assigns.selected_object_keys, filtered_keys)
      end

    {:noreply, assign(socket, :selected_object_keys, selected)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_object_keys, MapSet.new())}
  end

  @impl true
  def handle_event("toggle_subscription_selection", params, socket) do
    case subscription_key_from_params(params) do
      {:ok, key} ->
        selected = toggle_set_member(socket.assigns.selected_subscription_keys, key)
        {:noreply, assign(socket, :selected_subscription_keys, selected)}

      _err ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_select_all_subscriptions", _params, socket) do
    all_keys = subscription_keys(socket.assigns.subscriptions)

    all_selected? =
      all_keys != MapSet.new() and
        MapSet.subset?(all_keys, socket.assigns.selected_subscription_keys)

    selected =
      if all_selected? do
        MapSet.difference(socket.assigns.selected_subscription_keys, all_keys)
      else
        MapSet.union(socket.assigns.selected_subscription_keys, all_keys)
      end

    {:noreply, assign(socket, :selected_subscription_keys, selected)}
  end

  @impl true
  def handle_event("clear_subscription_selection", _params, socket) do
    {:noreply, assign(socket, :selected_subscription_keys, MapSet.new())}
  end

  @impl true
  def handle_event("unsubscribe_all_cov", _params, socket) do
    device_id = socket.assigns.device_id

    results =
      Enum.map(socket.assigns.subscriptions, fn sub ->
        SubscriptionManager.unsubscribe(device_id, sub.object_id, sub.property)
      end)

    failed = Enum.count(results, &match?({:error, _err}, &1))
    ok = length(results) - failed

    {:noreply,
     socket
     |> assign(:selected_subscription_keys, MapSet.new())
     |> refresh_cov_state()
     |> put_flash(
       :info,
       gt("Alle COV gekündigt: %{ok} erfolgreich, %{failed} fehlgeschlagen.",
         ok: ok,
         failed: failed
       )
     )}
  end

  @impl true
  def handle_event("resubscribe_selected_subscriptions", _params, socket) do
    device_id = socket.assigns.device_id

    results =
      socket.assigns.subscriptions
      |> selected_subscriptions(socket.assigns.selected_subscription_keys)
      |> Enum.map(&resubscribe_subscription(device_id, &1))

    failed = Enum.count(results, &match?({:error, _err}, &1))
    ok = length(results) - failed

    {:noreply,
     socket
     |> assign(:selected_subscription_keys, MapSet.new())
     |> refresh_cov_state()
     |> put_flash(
       :info,
       gt("COV erneut abonniert: %{ok} erfolgreich, %{failed} fehlgeschlagen.",
         ok: ok,
         failed: failed
       )
     )}
  end

  @impl true
  def handle_event("unsubscribe_selected_subscriptions", _params, socket) do
    device_id = socket.assigns.device_id

    results =
      socket.assigns.selected_subscription_keys
      |> MapSet.to_list()
      |> Enum.map(fn {type, instance, property} ->
        object_id = %ObjectIdentifier{type: type, instance: instance}
        SubscriptionManager.unsubscribe(device_id, object_id, property)
      end)

    failed = Enum.count(results, &match?({:error, _err}, &1))
    ok = length(results) - failed

    {:noreply,
     socket
     |> assign(:selected_subscription_keys, MapSet.new())
     |> refresh_cov_state()
     |> put_flash(
       :info,
       gt("COV gekündigt: %{ok} erfolgreich, %{failed} fehlgeschlagen.",
         ok: ok,
         failed: failed
       )
     )}
  end

  @impl true
  def handle_event("subscribe_selected_cov", _params, socket) do
    device_id = socket.assigns.device_id

    results =
      socket.assigns.selected_object_keys
      |> cov_subscribable_keys(socket.assigns.selectable_object_keys)
      |> Enum.map(fn {type, instance} ->
        object_id = %ObjectIdentifier{type: type, instance: instance}
        SubscriptionManager.subscribe(device_id, object_id, :present_value)
      end)

    failed = Enum.count(results, &match?({:error, _err}, &1))
    ok = length(results) - failed

    socket =
      socket
      |> refresh_cov_state()
      |> put_flash(
        :info,
        gt("COV abonniert: %{ok} erfolgreich, %{failed} fehlgeschlagen.",
          ok: ok,
          failed: failed
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("unsubscribe_selected_cov", _params, socket) do
    device_id = socket.assigns.device_id

    results =
      socket.assigns.selected_object_keys
      |> cov_subscribable_keys(socket.assigns.selectable_object_keys)
      |> Enum.map(fn {type, instance} ->
        object_id = %ObjectIdentifier{type: type, instance: instance}
        SubscriptionManager.unsubscribe(device_id, object_id, :present_value)
      end)

    failed = Enum.count(results, &match?({:error, _err}, &1))
    ok = length(results) - failed

    socket =
      socket
      |> refresh_cov_state()
      |> put_flash(
        :info,
        gt("COV gekündigt: %{ok} erfolgreich, %{failed} fehlgeschlagen.",
          ok: ok,
          failed: failed
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_write_modal", %{"type" => type, "instance" => instance}, socket) do
    with {:ok, type_atom} <- parse_type(type),
         {instance_int, ""} <- Integer.parse(instance),
         object when not is_nil(object) <- find_object(socket, type_atom, instance_int) do
      if Map.get(object, :writable, false) do
        socket =
          socket
          |> assign(:write_modal, object)
          |> assign(:write_priority, PropertyWriter.default_priority())

        {:noreply, refresh_write_modal_priority(socket, type_atom, instance_int)}
      else
        {:noreply, put_flash(socket, :error, gt("Present Value ist schreibgeschützt."))}
      end
    else
      _err -> {:noreply, put_flash(socket, :error, gt("Objekt nicht gefunden."))}
    end
  end

  @impl true
  def handle_event("close_write_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:write_modal, nil)
     |> assign(:writing_present_value, false)}
  end

  @impl true
  def handle_event("set_write_priority", %{"priority" => priority}, socket) do
    case Integer.parse(priority) do
      {p, ""} when p in 1..16 -> {:noreply, assign(socket, :write_priority, p)}
      _parse -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("write_present_value", params, socket) do
    form_params = BacViewWeb.WriteFormParams.normalize(params)
    value = Map.get(form_params, "value", "")
    priority = BacViewWeb.WriteFormParams.priority(params, socket.assigns.write_priority)

    with %{type: type, instance: instance} <- socket.assigns.write_modal,
         object_id <- %ObjectIdentifier{type: type, instance: instance},
         hint <- PropertyWriter.prop_hint_from_object(socket.assigns.write_modal),
         {:ok, parsed} <- PropertyWriter.parse_input(value, hint),
         {:ok, socket} <- write_present_value(socket, object_id, parsed, priority) do
      {:noreply, assign(socket, :write_priority, priority)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, gt("Kein Objekt zum Schreiben ausgewählt."))}

      {:error, :empty_value} ->
        {:noreply, put_flash(socket, :error, gt("Bitte einen Wert eingeben."))}

      {:error, {:write_failed, reason}} ->
        {:noreply, write_failed(socket, reason)}

      {:error, {:read_back_failed, reason}} ->
        {:noreply, read_back_failed(socket, reason)}

      {:error, {:verify_mismatch, _written, read}} ->
        {:noreply, verify_mismatch_present_value(socket, read)}

      {:error, reason} ->
        {:noreply, write_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("reset_present_value", _params, socket) do
    with %{type: type, instance: instance} <- socket.assigns.write_modal,
         object_id <- %ObjectIdentifier{type: type, instance: instance},
         {:ok, socket} <- write_present_value(socket, object_id, nil) do
      {:noreply, socket}
    else
      {:error, {:read_back_failed, reason}} ->
        {:noreply, read_back_failed(socket, reason)}

      {:error, {:verify_mismatch, _written, read}} ->
        {:noreply, verify_mismatch_present_value(socket, read)}

      _err ->
        {:noreply, put_flash(socket, :error, gt("Priorität zurücksetzen fehlgeschlagen."))}
    end
  end

  @impl true
  def handle_event("reveal_in_flat_list", %{"type" => type, "instance" => instance}, socket) do
    with {:ok, type_atom} <- parse_type(type),
         instance_int <- String.to_integer(instance) do
      {:noreply,
       socket
       |> push_patch(
         to:
           device_tab_path(socket.assigns.device_id, "objects",
             search: socket.assigns.search,
             types: socket.assigns.type_filter,
             status: socket.assigns.status_filter,
             sort: socket.assigns.sort_by,
             dir: socket.assigns.sort_dir
           )
       )
       |> push_event("scroll_to_object", %{type: type_atom, instance: instance_int})}
    else
      _err -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in [
             "toggle_device_services_menu",
             "close_device_services_menu",
             "open_device_service_modal",
             "close_device_service_modal",
             "device_service_form_change",
             "execute_device_service"
           ] do
    case DeviceServicesHandlers.handle_event(event, params, socket) do
      {:noreply, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  def handle_event("refresh_device", _params, socket) do
    {:noreply, start_device_reload(socket)}
  end

  @impl true
  def handle_event("subscribe_notification_classes", _params, socket) do
    NotificationClassRecipient.subscribe_all(
      socket.assigns.device_id,
      self(),
      objects: socket.assigns.objects
    )

    {:noreply,
     socket
     |> assign(:nc_subscribing, true)
     |> assign(:nc_progress, %{done: 0, total: nc_object_count(socket.assigns.objects)})}
  end

  @impl true
  def handle_event("unsubscribe_notification_classes", _params, socket) do
    NotificationClassRecipient.unsubscribe_all(
      socket.assigns.device_id,
      self(),
      objects: socket.assigns.objects
    )

    {:noreply,
     socket
     |> assign(:nc_subscribing, true)
     |> assign(:nc_progress, %{done: 0, total: nc_object_count(socket.assigns.objects)})}
  end

  @impl true
  def handle_event("refresh_alarms", _params, socket) do
    socket = assign(socket, :alarms_refreshing, true)

    case AlarmEvent.refresh(socket.assigns.device_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:alarms_refreshing, false)
         |> refresh_alarm_state()
         |> put_flash(:info, gt("Ereignisse aktualisiert."))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:alarms_refreshing, false)
         |> LiveFlash.put_error(:fetch_events, reason)}
    end
  end

  @impl true
  def handle_event("export_events", %{"format" => format}, socket) do
    export_format =
      case format do
        "csv" -> :csv
        _format -> :json
      end

    case AlarmEvent.export(socket.assigns.device_id, export_format) do
      {:ok, content} ->
        ext = if export_format == :csv, do: "csv", else: "json"
        mime = if export_format == :csv, do: "text/csv", else: "application/json"
        filename = "bacview-device-#{socket.assigns.device_id}-events.#{ext}"

        {:noreply,
         push_event(socket, "download_file", %{
           content: content,
           filename: filename,
           mime: mime
         })}

      {:error, reason} ->
        {:noreply, LiveFlash.put_error(socket, :export_events, reason)}
    end
  end

  @shortcut_tabs %{
    1 => "hierarchy",
    2 => "objects",
    3 => "subscriptions",
    4 => "alarms"
  }

  @alarm_sub_tabs %{
    1 => "event_information",
    2 => "active_alarms",
    3 => "notifications"
  }

  @cov_sub_tabs %{
    1 => "subscriptions",
    2 => "notifications"
  }

  @hierarchy_sub_tabs %{
    1 => "explorer",
    2 => "tree"
  }

  @impl true
  def handle_event("global_keydown", params, socket) do
    key = Map.get(params, "key", "")
    code = Map.get(params, "code", "")
    shift = Map.get(params, "shift", false)

    cond do
      BacViewWeb.Shortcuts.go_up_pressed?(params) ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      shift && socket.assigns.tab == "alarms" &&
          Map.has_key?(@alarm_sub_tabs, BacViewWeb.Shortcuts.digit_index(code)) ->
        alarm_view = Map.fetch!(@alarm_sub_tabs, BacViewWeb.Shortcuts.digit_index(code))

        {:noreply,
         push_patch(
           socket,
           to:
             device_tab_path(
               socket.assigns.device_id,
               "alarms",
               Keyword.put(device_tab_opts(socket.assigns), :alarm_view, alarm_view)
             )
         )}

      shift && socket.assigns.tab == "subscriptions" &&
          Map.has_key?(@cov_sub_tabs, BacViewWeb.Shortcuts.digit_index(code)) ->
        cov_view = Map.fetch!(@cov_sub_tabs, BacViewWeb.Shortcuts.digit_index(code))

        {:noreply,
         push_patch(
           socket,
           to:
             device_tab_path(
               socket.assigns.device_id,
               "subscriptions",
               Keyword.put(device_tab_opts(socket.assigns), :cov_view, cov_view)
             )
         )}

      shift && socket.assigns.tab == "hierarchy" &&
          Map.has_key?(@hierarchy_sub_tabs, BacViewWeb.Shortcuts.digit_index(code)) ->
        hierarchy_view = Map.fetch!(@hierarchy_sub_tabs, BacViewWeb.Shortcuts.digit_index(code))

        {:noreply,
         push_patch(
           socket,
           to:
             device_tab_path(
               socket.assigns.device_id,
               "hierarchy",
               Keyword.put(device_tab_opts(socket.assigns), :hierarchy_view, hierarchy_view)
             )
         )}

      Map.has_key?(@shortcut_tabs, BacViewWeb.Shortcuts.digit_index(code)) && not shift ->
        tab = Map.fetch!(@shortcut_tabs, BacViewWeb.Shortcuts.digit_index(code))

        {:noreply,
         push_patch(
           socket,
           to: device_tab_path(socket.assigns.device_id, tab, device_tab_opts(socket.assigns))
         )}

      Map.has_key?(@shortcut_tabs, digit_key_index(key)) && not shift ->
        tab = Map.fetch!(@shortcut_tabs, digit_key_index(key))

        {:noreply,
         push_patch(
           socket,
           to: device_tab_path(socket.assigns.device_id, tab, device_tab_opts(socket.assigns))
         )}

      BacViewWeb.Shortcuts.refresh_key?(key) ->
        {:noreply, start_device_reload(socket)}

      true ->
        BacViewWeb.Shortcuts.handle(params, socket)
    end
  end

  @impl true
  def handle_event("toggle_shortcuts", _params, socket) do
    {:noreply, BacViewWeb.Shortcuts.toggle_shortcuts(socket)}
  end

  @impl true
  def handle_event("toggle_alarm_popup", _params, socket) do
    {:noreply,
     ActiveAlarmsAssigns.toggle(socket,
       device_id: socket.assigns.device_id,
       objects: socket.assigns.objects
     )}
  end

  @impl true
  def handle_event("close_alarm_popup", _params, socket) do
    {:noreply, ActiveAlarmsAssigns.close(socket)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  defp refresh_notification_class_counts(socket) do
    socket
    |> assign(
      :nc_enrolled_count,
      NotificationClassRecipient.enrolled_count(socket.assigns.device_id)
    )
    |> assign(:nc_total, nc_object_count(socket.assigns.objects))
  end

  defp spawn_nc_sync(socket) do
    if nc_object_count(socket.assigns.objects) > 0 do
      parent = self()
      device_id = socket.assigns.device_id
      objects = socket.assigns.objects

      Task.start(fn ->
        result = NotificationClassRecipient.sync_enrollment_state(device_id, objects)
        send(parent, {:nc_sync_done, result})
      end)
    end

    socket
  end

  defp nc_object_count(objects) when is_list(objects) do
    Enum.count(objects, &(&1.type == :notification_class))
  end

  defp nc_bulk_flash(socket, :subscribe, _enrolled, 0) do
    put_flash(socket, :warning, gt("Keine Meldungsklassen auf diesem Gerät gefunden."))
  end

  defp nc_bulk_flash(socket, :subscribe, enrolled, _total) when enrolled > 0 do
    put_flash(socket, :info, gt("%{count} Meldungsklassen eingetragen.", count: enrolled))
  end

  defp nc_bulk_flash(socket, :subscribe, _enrolled, _total) do
    LiveFlash.put_error(socket, :notification_class_recipient, :enrollment_failed)
  end

  defp nc_bulk_flash(socket, :unsubscribe, 0, _total) do
    put_flash(socket, :info, gt("Aus allen Meldungsklassen entfernt."))
  end

  defp nc_bulk_flash(socket, :unsubscribe, enrolled, _total) do
    put_flash(
      socket,
      :warning,
      gt("%{count} Meldungsklassen noch eingetragen.", count: enrolled)
    )
  end

  defp refresh_alarm_popup(socket) do
    ActiveAlarmsAssigns.refresh(socket,
      device_id: socket.assigns.device_id,
      objects: socket.assigns.objects
    )
  end

  defp refresh_alarm_state(socket) do
    device_id = socket.assigns.device_id
    events = AlarmEvent.list_polled_events(device_id)
    notifications = AlarmEvent.list_notifications(device_id)
    summary = AlarmEvent.summary(device_id)
    active_alarm_objects = active_alarm_objects(socket.assigns.objects)

    socket
    |> assign(:events, events)
    |> assign(:notifications, notifications)
    |> assign(:active_alarm_objects, active_alarm_objects)
    |> assign(:alarm_summary, summary)
    |> assign(:alarm_tab_count, alarm_tab_count(summary, active_alarm_objects))
  end

  defp refresh_active_alarm_objects(socket) do
    active_alarm_objects = active_alarm_objects(socket.assigns.objects)

    socket
    |> assign(:active_alarm_objects, active_alarm_objects)
    |> assign(
      :alarm_tab_count,
      alarm_tab_count(socket.assigns.alarm_summary, active_alarm_objects)
    )
  end

  defp active_alarm_objects(objects) when is_list(objects) do
    objects
    |> Enum.filter(&object_in_active_alarm?/1)
    |> Enum.sort_by(fn obj -> {obj.type, obj.instance} end, :asc)
  end

  defp object_in_active_alarm?(obj) do
    flags = Map.get(obj, :status_flags)

    flags &&
      Enum.any?([:in_alarm, :fault], fn flag ->
        flag in StatusFlagsIcons.active_flags(flags)
      end)
  end

  defp alarm_tab_count(summary, active_alarm_objects) do
    max(summary.active_count, length(active_alarm_objects))
  end

  defp alarm_view_paths(device_id, opts) do
    %{
      "event_information" =>
        device_tab_path(device_id, "alarms", Keyword.put(opts, :alarm_view, "event_information")),
      "active_alarms" =>
        device_tab_path(device_id, "alarms", Keyword.put(opts, :alarm_view, "active_alarms")),
      "notifications" =>
        device_tab_path(device_id, "alarms", Keyword.put(opts, :alarm_view, "notifications"))
    }
  end

  defp refresh_cov_state(socket) do
    subs = SubscriptionManager.list_active(socket.assigns.device_id)

    keys =
      subs
      |> Enum.map(fn sub ->
        {sub.object_id.type, sub.object_id.instance, sub.property}
      end)
      |> MapSet.new()

    socket
    |> assign(:subscriptions, subs)
    |> assign(:subscribed_keys, keys)
    |> assign(:cov_count, length(subs))
  end

  defp refresh_cov_notifications(socket) do
    assign(
      socket,
      :cov_notifications,
      SubscriptionManager.list_notifications(socket.assigns.device_id)
    )
  end

  defp apply_active_hierarchy(socket) do
    sv_hierarchy = Map.get(socket.assigns, :sv_hierarchy, empty_hierarchy())
    objects = Map.get(socket.assigns, :objects, [])
    split = Map.get(socket.assigns, :hierarchy_split)

    hierarchy =
      case split do
        nil ->
          sv_hierarchy

        split_config ->
          NameHierarchyBuilder.build(objects, split_config)
      end

    hierarchy = normalize_hierarchy(hierarchy)
    tree_expanded = default_expanded(hierarchy.roots)

    socket
    |> assign(:hierarchy, hierarchy)
    |> assign(:hierarchy_source, if(split, do: :name, else: :structured))
    |> assign(:tree_roots, hierarchy.roots)
    |> assign(:tree_match_count, count_tree_nodes(hierarchy.roots))
    |> assign(:tree_expanded, tree_expanded)
    |> refresh_hierarchy_explorer()
  end

  defp refresh_hierarchy_explorer(socket) do
    roots = Map.get(socket.assigns.hierarchy, :roots, [])
    path = Map.get(socket.assigns, :hierarchy_path, [])
    objects = Map.get(socket.assigns, :objects, [])
    device_id = socket.assigns.device_id
    url_opts = hierarchy_url_opts(socket)

    entries =
      HierarchyExplorer.folder_entries(roots, path, objects,
        selectable_keys: Map.get(socket.assigns, :selectable_object_keys, MapSet.new())
      )

    search = Map.get(socket.assigns, :explorer_search, "")
    {entries, match_count} = HierarchyExplorer.filter_entries(entries, search)

    path_links =
      roots
      |> HierarchyExplorer.breadcrumbs(path)
      |> Enum.map(fn {label, crumb_path} ->
        {label, crumb_path,
         DeviceUrl.device_path(
           device_id,
           Keyword.put(url_opts, :hierarchy_path, crumb_path)
         )}
      end)

    root_path =
      DeviceUrl.device_path(device_id, Keyword.put(url_opts, :hierarchy_path, []))

    socket
    |> assign(:hierarchy_entries, entries)
    |> assign(:explorer_match_count, match_count)
    |> assign(:hierarchy_path_links, path_links)
    |> assign(:hierarchy_root_path, root_path)
  end

  defp hierarchy_url_opts(socket) do
    [
      tab: "hierarchy",
      hierarchy_view: socket.assigns.hierarchy_view,
      hierarchy_path: socket.assigns.hierarchy_path,
      h_split: HierarchySplit.encode(socket.assigns.hierarchy_split),
      search: socket.assigns.search,
      types: socket.assigns.type_filter,
      status: socket.assigns.status_filter,
      sort: socket.assigns.sort_by,
      dir: socket.assigns.sort_dir
    ]
  end

  defp name_hierarchy_device_opts(socket, split) do
    [
      tab: "hierarchy",
      hierarchy_view: socket.assigns.hierarchy_view,
      hierarchy_path: [],
      h_split: HierarchySplit.encode(split),
      search: socket.assigns.search,
      types: socket.assigns.type_filter,
      status: socket.assigns.status_filter,
      sort: socket.assigns.sort_by,
      dir: socket.assigns.sort_dir
    ]
  end

  defp hierarchy_view_paths(device_id, opts) do
    explorer_opts = Keyword.merge(opts, tab: "hierarchy", hierarchy_view: "explorer")
    tree_opts = Keyword.merge(opts, tab: "hierarchy", hierarchy_view: "tree")

    %{
      "explorer" => DeviceUrl.device_path(device_id, explorer_opts),
      "tree" => DeviceUrl.device_path(device_id, tree_opts),
      "objects_fallback" =>
        device_tab_path(device_id, "objects",
          search: Keyword.get(opts, :search, ""),
          types: Keyword.get(opts, :types, []),
          status: Keyword.get(opts, :status, []),
          sort: Keyword.get(opts, :sort, nil),
          dir: Keyword.get(opts, :dir, :asc)
        )
    }
  end

  defp cov_view_paths(device_id, opts) do
    %{
      "subscriptions" =>
        device_tab_path(device_id, "subscriptions", Keyword.put(opts, :cov_view, "subscriptions")),
      "notifications" =>
        device_tab_path(device_id, "subscriptions", Keyword.put(opts, :cov_view, "notifications"))
    }
  end

  defp parse_type(type) when is_binary(type) do
    {:ok, String.to_existing_atom(type)}
  rescue
    ArgumentError -> :error
  end

  defp parse_skip_mode("value"), do: {:ok, :value}
  defp parse_skip_mode("all"), do: {:ok, true}
  defp parse_skip_mode(_mode), do: :error

  defp parse_status(status) when is_binary(status) do
    case ObjectTable.normalize_status_flag(status) do
      nil -> :error
      flag -> {:ok, flag}
    end
  end

  defp parse_property("present_value"), do: {:ok, :present_value}

  defp parse_property(prop) when is_atom(prop), do: {:ok, prop}

  defp parse_property(prop) when is_binary(prop) do
    {:ok, String.to_existing_atom(prop)}
  rescue
    ArgumentError -> {:ok, prop}
  end

  defp load_cov_chart_data(%{
         device_id: device_id,
         subscription: subscription,
         notifications: notifications,
         objects: objects,
         start_value: start_value,
         end_value: end_value
       }) do
    with {:ok, filtered, start_dt, end_dt} <-
           select_cov_chart_notifications(notifications, subscription, start_value, end_value) do
      object = find_chart_object(objects, subscription.object_id)

      data =
        CovNotificationChart.build(filtered, subscription,
          device_id: device_id,
          object: object,
          start_dt: start_dt,
          end_dt: end_dt
        )

      {:ok, %{data: data, records: filtered, start_dt: start_dt, end_dt: end_dt}}
    end
  end

  defp select_cov_chart_notifications(notifications, subscription, start_value, end_value) do
    scoped =
      CovNotificationChart.notifications_for(
        notifications,
        subscription.object_id,
        subscription.property
      )

    if blank_chart_range?(start_value) and blank_chart_range?(end_value) do
      {start_dt, end_dt} = CovNotificationChart.range_from_notifications(scoped)
      {:ok, scoped, start_dt, end_dt}
    else
      with {:ok, start_dt} <- parse_chart_range(start_value, :start),
           {:ok, end_dt} <- parse_chart_range(end_value, :end),
           :ok <- validate_chart_range(start_dt, end_dt) do
        filtered =
          CovNotificationChart.filter_notifications_by_range(scoped, start_dt, end_dt)

        {:ok, filtered, start_dt, end_dt}
      end
    end
  end

  defp find_chart_object(objects, %{type: type, instance: instance}) when is_list(objects) do
    Enum.find(objects, &(&1.type == type and &1.instance == instance))
  end

  defp find_chart_object(_objects, _object_id), do: nil

  defp blank_chart_range?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_chart_range?(_value), do: true

  defp parse_chart_range(value, _fallback) when is_binary(value) do
    case TrendLogChart.parse_form_value(value) do
      {:ok, dt} -> {:ok, dt}
      :error -> {:error, :invalid_datetime_range}
    end
  end

  defp parse_chart_range(_value, _fallback), do: {:error, :invalid_datetime_range}

  defp parse_chart_datetime(value) when is_binary(value) do
    case TrendLogChart.parse_form_value(value) do
      {:ok, dt} -> dt
      :error -> nil
    end
  end

  defp parse_chart_datetime(_value), do: nil

  defp validate_chart_range(start_dt, end_dt) do
    if NaiveDateTime.compare(start_dt, end_dt) == :gt do
      {:error, :invalid_datetime_range}
    else
      :ok
    end
  end

  defp chart_has_data?(%{series: series}) when is_list(series) do
    Enum.any?(series, fn %{points: points} -> points != [] end)
  end

  defp chart_has_data?(_data), do: false

  defp cov_chart_download(socket, format) do
    case socket.assigns.cov_chart_data do
      data when is_map(data) ->
        subscription = socket.assigns.cov_chart_subscription
        start_dt = parse_chart_datetime(socket.assigns.cov_chart_start)
        end_dt = parse_chart_datetime(socket.assigns.cov_chart_end)

        {content, mime, ext} =
          case format do
            :json ->
              {TrendLogExport.to_json(data,
                 object: %{
                   type: subscription.object_id.type,
                   instance: subscription.object_id.instance,
                   property: subscription.property
                 },
                 start_dt: start_dt,
                 end_dt: end_dt
               ), "application/json", "json"}

            _format ->
              {TrendLogExport.to_csv(data), "text/csv", "csv"}
          end

        filename =
          CovNotificationChart.filename(
            subscription.object_id.type,
            subscription.object_id.instance,
            subscription.property,
            start_dt,
            end_dt,
            ext
          )

        push_event(socket, "download_file", %{
          content: content,
          filename: filename,
          mime: mime
        })

      _socket ->
        socket
    end
  end

  defp chart_event_payload(%{series: series} = data) when is_list(series) do
    payload_series =
      Enum.map(series, fn %{
                            id: id,
                            label: label,
                            unit_label: unit_label,
                            scale_id: scale_id,
                            points: points
                          } ->
        %{
          id: id,
          label: label,
          unit_label: unit_label,
          scale_id: scale_id,
          points: Enum.map(points, fn %{t: t, v: v} -> %{t: t, v: v} end)
        }
      end)

    if chart_has_data?(data) do
      Map.put(data, :series, payload_series)
    else
      %{
        series: [],
        scales: Map.get(data, :scales, []),
        markers: Map.get(data, :markers, []),
        range: Map.get(data, :range, %{}),
        empty_label: "Keine plottbaren COV-Meldungen im gewählten Zeitraum."
      }
    end
  end

  defp chart_event_payload(_data),
    do: %{series: [], scales: [], empty_label: "Keine Daten geladen."}

  defp default_expanded(roots) do
    roots
    |> Enum.map(&BacView.BACnet.HierarchyNode.id/1)
    |> MapSet.new()
  end

  defp expand_all(roots) do
    roots
    |> flatten_ids()
    |> MapSet.new()
  end

  defp flatten_ids(nodes) do
    Enum.flat_map(nodes, fn node ->
      [BacView.BACnet.HierarchyNode.id(node) | flatten_ids(node.children)]
    end)
  end

  defp count_tree_nodes(roots) do
    {_filtered, count} = HierarchyBuilder.filter_tree(roots, "")
    count
  end

  defp object_label(%{object_id: %{type: type, instance: instance}}),
    do: "#{type}:#{instance}"

  defp start_device_reload(socket) do
    send(self(), {:load_device, true})

    socket
    |> assign(:loading, true)
    |> assign(:loading_in_progress, true)
    |> assign(:load_progress, %{stage: :connecting, done: 0, total: nil})
  end

  defp apply_loaded_device(socket, loaded) do
    sv_hierarchy = loaded |> Map.get(:hierarchy, empty_hierarchy()) |> normalize_hierarchy()
    objects = normalize_objects(loaded.objects)

    hierarchy_split =
      NameHierarchyCache.resolve(
        socket.assigns.device_id,
        socket.assigns.hierarchy_split,
        objects
      )

    socket
    |> assign(:device, loaded)
    |> assign(:objects, objects)
    |> assign(:selectable_object_keys, selectable_object_keys(objects))
    |> assign(:sv_hierarchy, sv_hierarchy)
    |> assign(:hierarchy_split, hierarchy_split)
    |> assign(:loading, false)
    |> assign(:load_progress, nil)
    |> apply_active_hierarchy()
    |> refresh_cov_state()
    |> refresh_cov_notifications()
    |> refresh_active_alarm_objects()
    |> refresh_notification_class_counts()
    |> spawn_nc_sync()
  end

  defp normalize_objects(objects) when is_list(objects) do
    Enum.map(objects, fn obj ->
      obj
      |> Map.put_new(:description, nil)
      |> Map.put_new(:commandable, false)
      |> Map.put_new(:writable, false)
      |> Map.put_new(:active_priority, nil)
      |> Map.put_new(:active_priority_value_formatted, nil)
    end)
  end

  defp selectable_object_keys(objects) when is_list(objects) do
    objects
    |> Enum.reject(&(&1.type == :structured_view))
    |> Enum.map(fn obj -> {obj.type, obj.instance} end)
    |> MapSet.new()
  end

  defp filtered_object_keys(socket) do
    socket.assigns.objects
    |> ObjectTable.filtered_objects(
      socket.assigns.search,
      socket.assigns.type_filter,
      socket.assigns.status_filter
    )
    |> Enum.map(fn obj -> {obj.type, obj.instance} end)
    |> MapSet.new()
  end

  defp object_selection_keys(socket, type, instance)
       when type in [:structured_view, :name_folder] do
    case HierarchyExplorer.find_node(
           Map.get(socket.assigns.hierarchy, :roots, []),
           {type, instance}
         ) do
      nil ->
        MapSet.new()

      node ->
        HierarchyExplorer.descendant_selectable_keys(node, socket.assigns.selectable_object_keys)
    end
  end

  defp object_selection_keys(socket, type, instance) do
    key = {type, instance}

    if MapSet.member?(socket.assigns.selectable_object_keys, key),
      do: MapSet.new([key]),
      else: MapSet.new()
  end

  defp hierarchy_visible_selection_keys(socket) do
    selectable = socket.assigns.selectable_object_keys

    case {socket.assigns.tab, socket.assigns.hierarchy_view} do
      {"hierarchy", "explorer"} ->
        HierarchyExplorer.visible_selection_keys(socket.assigns.hierarchy_entries, selectable)

      {"hierarchy", "tree"} ->
        HierarchyExplorer.tree_visible_selection_keys(socket.assigns.tree_roots, selectable)

      _tab ->
        MapSet.new()
    end
  end

  defp selection_group_selected?(selected_keys, group_keys) do
    group_keys != MapSet.new() and MapSet.subset?(group_keys, selected_keys)
  end

  defp cov_subscribable_keys(selected_keys, selectable_keys) do
    selected_keys
    |> MapSet.intersection(selectable_keys)
    |> MapSet.to_list()
  end

  defp subscription_keys(subscriptions) when is_list(subscriptions) do
    subscriptions
    |> Enum.map(&subscription_key/1)
    |> MapSet.new()
  end

  defp subscription_key(sub) do
    {sub.object_id.type, sub.object_id.instance, sub.property}
  end

  defp selected_subscriptions(subscriptions, selected_keys) when is_list(subscriptions) do
    Enum.filter(subscriptions, fn sub ->
      MapSet.member?(selected_keys, subscription_key(sub))
    end)
  end

  defp resubscribe_subscription(device_id, sub) do
    SubscriptionManager.subscribe(device_id, sub.object_id, sub.property,
      lifetime: sub.lifetime,
      confirmed: sub.confirmed,
      process_id: sub.process_id,
      subscribe_service: Map.get(sub, :subscribe_service, :subscribe_cov_property)
    )
  end

  defp subscription_key_from_params(params) do
    with {:ok, type_atom} <- parse_type(params["type"]),
         {instance_int, ""} <- Integer.parse(params["instance"]),
         {:ok, property} <- parse_property(params["property"] || "present_value") do
      {:ok, {type_atom, instance_int, property}}
    else
      _err -> :error
    end
  end

  defp toggle_set_member(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  defp find_object(socket, type, instance) do
    Enum.find(socket.assigns.objects, fn obj ->
      obj.type == type and obj.instance == instance
    end)
  end

  defp write_present_value(socket, object_id, value, priority \\ nil) do
    object = socket.assigns.write_modal
    device_id = socket.assigns.device_id
    priority = priority || socket.assigns.write_priority

    opts = PropertyWriter.write_opts(object, :present_value, priority)

    socket = assign(socket, :writing_present_value, true)

    with :ok <- DeviceSession.write_property(device_id, object_id, :present_value, value, opts),
         {:ok, read_value} <- read_back_property(device_id, object_id, :present_value, value),
         {:ok, priority_info} <-
           read_back_priority_info(device_id, object_id, object, read_value),
         {:ok, status_flags} <- read_back_status_flags(device_id, object_id) do
      message =
        if value == nil do
          gt("Priorität %{priority} zurückgesetzt (null).", priority: priority)
        else
          gt("Present Value erfolgreich geschrieben.")
        end

      coerced =
        PropertyFormatter.coerce_present_value(read_value, %{
          type: object_id.type,
          units: Map.get(object, :units)
        })

      DeviceSession.publish_property_update(device_id, object_id, :present_value, coerced)

      if normalized_flags = StatusFlagsParser.normalize(status_flags) do
        DeviceSession.publish_property_update(
          device_id,
          object_id,
          :status_flags,
          normalized_flags
        )
      end

      {:ok,
       socket
       |> assign(:writing_present_value, false)
       |> assign(:write_modal, nil)
       |> update_object_present_value(
         object_id.type,
         object_id.instance,
         read_value,
         priority_info
       )
       |> maybe_update_object_status_flags(object_id.type, object_id.instance, status_flags)
       |> refresh_active_alarm_objects()
       |> put_flash(:info, message)}
    else
      {:error, {:read_back_failed, _reason}} = err ->
        err

      {:error, {:verify_mismatch, _written, _read}} = err ->
        err

      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  defp read_back_property(device_id, object_id, property, written_value) do
    case DeviceSession.read_property(device_id, object_id, property) do
      {:ok, read_value} ->
        if PropertyWriter.values_match?(written_value, read_value) do
          {:ok, read_value}
        else
          {:error, {:verify_mismatch, written_value, read_value}}
        end

      {:error, reason} ->
        {:error, {:read_back_failed, reason}}
    end
  end

  defp read_back_priority_info(device_id, object_id, %{commandable: true} = object, _read_value) do
    case DeviceSession.read_property(device_id, object_id, :priority_array) do
      {:ok, priority_array} ->
        {:ok,
         PropertyWriter.active_priority_info(Map.put(object, :priority_array, priority_array))}

      {:error, reason} ->
        {:error, {:read_back_failed, reason}}
    end
  end

  defp read_back_priority_info(_device_id, _object_id, _object, _read_value), do: {:ok, %{}}

  defp refresh_write_modal_priority(socket, _type, _instance) do
    case socket.assigns.write_modal do
      %{commandable: true, type: type, instance: instance} ->
        parent = self()
        device_id = socket.assigns.device_id
        object_id = %ObjectIdentifier{type: type, instance: instance}

        Task.start(fn ->
          case DeviceSession.read_property(device_id, object_id, :priority_array) do
            {:ok, priority_array} ->
              send(parent, {:write_modal_priority, type, instance, priority_array})

            _err ->
              :ok
          end
        end)

        socket

      _modal ->
        socket
    end
  end

  defp apply_write_modal_priority(socket, type, instance, priority_array) do
    case socket.assigns.write_modal do
      %{type: ^type, instance: ^instance} = object ->
        priority_info =
          PropertyWriter.active_priority_info(Map.put(object, :priority_array, priority_array))

        assign(socket, :write_modal, Map.merge(object, priority_info))

      _socket ->
        socket
    end
  end

  defp update_object_present_value(socket, type, instance, value, priority_info \\ %{}) do
    objects =
      Enum.map(socket.assigns.objects, fn obj ->
        if obj.type == type and obj.instance == instance do
          coerced = PropertyFormatter.coerce_present_value(value, obj)

          obj
          |> Map.merge(%{
            present_value: coerced,
            present_value_formatted: PropertyFormatter.format_present_value(coerced, obj),
            updated_at: DateTime.utc_now()
          })
          |> Map.merge(priority_info)
        else
          obj
        end
      end)

    assign(socket, :objects, objects)
  end

  defp maybe_update_object_status_flags(socket, _type, _instance, nil), do: socket

  defp maybe_update_object_status_flags(socket, type, instance, flags) do
    case StatusFlagsParser.normalize(flags) do
      nil ->
        socket

      normalized ->
        objects =
          Enum.map(socket.assigns.objects, fn obj ->
            if obj.type == type and obj.instance == instance do
              Map.merge(obj, %{
                status_flags: normalized,
                updated_at: DateTime.utc_now()
              })
            else
              obj
            end
          end)

        assign(socket, :objects, objects)
    end
  end

  defp read_back_status_flags(device_id, object_id) do
    case DeviceSession.read_property(device_id, object_id, :status_flags) do
      {:ok, flags} -> {:ok, flags}
      {:error, _err} -> {:ok, nil}
    end
  end

  defp write_error(socket, reason) do
    put_flash(
      assign(socket, :writing_present_value, false),
      :error,
      gt("Ungültiger Wert: %{reason}", reason: format_parse_error(reason))
    )
  end

  defp write_failed(socket, reason) do
    socket
    |> assign(:writing_present_value, false)
    |> LiveFlash.put_error(:write_property, reason)
  end

  defp read_back_failed(socket, reason) do
    socket
    |> assign(:writing_present_value, false)
    |> LiveFlash.put_error(:read_back_property, reason)
  end

  defp verify_mismatch_present_value(socket, read_value) do
    object = socket.assigns.write_modal

    socket
    |> assign(:writing_present_value, false)
    |> assign(:write_modal, nil)
    |> update_object_present_value(object.type, object.instance, read_value)
    |> put_flash(
      :error,
      gt(
        "Geschriebener Wert weicht vom gelesenen Present Value ab: %{value}",
        value: PropertyFormatter.format_value(read_value, Map.get(object, :units))
      )
    )
  end

  defp format_parse_error(:invalid_boolean), do: gt("erwartet true/false")
  defp format_parse_error(:invalid_number), do: gt("erwartet Zahl")
  defp format_parse_error(reason), do: inspect(reason)

  defp empty_hierarchy(),
    do: %{roots: [], empty?: true, structured_view_count: 0, source: :structured, split: nil}

  defp normalize_tab(tab) when tab in @valid_tabs, do: tab
  defp normalize_tab(_tab), do: @default_tab

  defp update_alarm_table_sort(socket, sort_by_key, sort_dir_key, column, normalize_column) do
    case normalize_column.(column) do
      nil ->
        socket

      column ->
        {sort_by, sort_dir} =
          BacViewWeb.AlarmTable.toggle_sort(
            Map.fetch!(socket.assigns, sort_by_key),
            Map.fetch!(socket.assigns, sort_dir_key),
            column
          )

        socket
        |> assign(sort_by_key, sort_by)
        |> assign(sort_dir_key, sort_dir)
    end
  end

  defp patch_objects_tab(socket, opts) do
    search = Keyword.get(opts, :search, socket.assigns.search)
    type_filter = Keyword.get(opts, :type_filter, socket.assigns.type_filter)
    type_filter_open = Keyword.get(opts, :type_filter_open, socket.assigns.type_filter_open)
    status_filter = Keyword.get(opts, :status_filter, socket.assigns.status_filter)
    status_filter_open = Keyword.get(opts, :status_filter_open, socket.assigns.status_filter_open)
    sort_by = Keyword.get(opts, :sort_by, socket.assigns.sort_by)
    sort_dir = Keyword.get(opts, :sort_dir, socket.assigns.sort_dir)

    path =
      DeviceUrl.device_path(socket.assigns.device_id,
        tab: "objects",
        search: search,
        types: type_filter,
        status: status_filter,
        sort: sort_by,
        dir: sort_dir
      )

    socket
    |> assign(:search, search)
    |> assign(:type_filter, type_filter)
    |> assign(:type_filter_open, type_filter_open)
    |> assign(:status_filter, status_filter)
    |> assign(:status_filter_open, status_filter_open)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> push_patch(to: path)
  end

  defp device_tab_path(device_id, tab, opts) when tab in @valid_tabs do
    search = Keyword.get(opts, :search, "")
    types = Keyword.get(opts, :types, [])
    status = Keyword.get(opts, :status, [])
    sort = Keyword.get(opts, :sort, nil)
    dir = Keyword.get(opts, :dir, :asc)
    alarm_view = Keyword.get(opts, :alarm_view, nil)
    cov_view = Keyword.get(opts, :cov_view, nil)
    hierarchy_view = Keyword.get(opts, :hierarchy_view, nil)
    hierarchy_path = Keyword.get(opts, :hierarchy_path, nil)
    hierarchy_split = Keyword.get(opts, :h_split, nil)

    url_opts = [
      tab: tab,
      search: search,
      types: types,
      status: status,
      sort: sort,
      dir: dir
    ]

    url_opts =
      if tab == "alarms" and alarm_view do
        Keyword.put(url_opts, :alarm_view, alarm_view)
      else
        url_opts
      end

    url_opts =
      if tab == "subscriptions" and cov_view do
        Keyword.put(url_opts, :cov_view, cov_view)
      else
        url_opts
      end

    url_opts =
      if tab == "hierarchy" do
        url_opts
        |> maybe_put(:hierarchy_view, hierarchy_view)
        |> maybe_put(:hierarchy_path, hierarchy_path)
        |> maybe_put(:h_split, hierarchy_split)
      else
        url_opts
      end

    DeviceUrl.device_path(device_id, url_opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp digit_key_index(key) when key in ~w(1 2 3 4), do: String.to_integer(key)
  defp digit_key_index(_key), do: nil

  defp device_tab_opts(assigns) do
    [
      tab: assigns.tab,
      search: assigns.search,
      types: assigns.type_filter,
      status: assigns.status_filter,
      sort: assigns.sort_by,
      dir: assigns.sort_dir,
      alarm_view: assigns.alarm_view,
      cov_view: assigns.cov_view,
      hierarchy_view: assigns.hierarchy_view,
      hierarchy_path: assigns.hierarchy_path,
      h_split: HierarchySplit.encode(assigns.hierarchy_split),
      device_id: assigns.device_id
    ]
  end

  defp resolve_hierarchy_split(socket, params) do
    url_split = DeviceUrl.normalize_hierarchy_split(Map.get(params, "h_split"))

    NameHierarchyCache.resolve(
      socket.assigns.device_id,
      url_split,
      Map.get(socket.assigns, :objects, [])
    )
  end

  defp normalize_hierarchy(hierarchy) when is_map(hierarchy) do
    %{
      roots: Map.get(hierarchy, :roots, []),
      empty?: Map.get(hierarchy, :empty?, true),
      structured_view_count: Map.get(hierarchy, :structured_view_count, 0),
      source: Map.get(hierarchy, :source, :structured),
      split: Map.get(hierarchy, :split)
    }
  end

  defp structured_hierarchy?(sv_hierarchy) do
    not Map.get(sv_hierarchy, :empty?, true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      locale={@locale}
      locale_version={@locale_version}
      show_shortcuts={@show_shortcuts}
      shortcuts_context={:device}
    >
      <:topbar_end>
        <%= for _ <- [@locale_version] do %>
          <ActiveAlarmsPopup.active_alarms_badge
            count={@alarm_tab_count}
            open={@alarm_popup_open}
            locale={@locale}
            locale_version={@locale_version}
          />
          <span :if={@cov_count > 0} class="bac-badge bac-badge-success">
            <.icon name="hero-signal" class="size-3" />
            {@cov_count} COV
          </span>
        <% end %>
      </:topbar_end>

      <%= for _ <- [{@locale_version, @device_service_menu}] do %>
      <div class="flex flex-col flex-1 min-h-0">
        <header class="bac-panel-header px-5">
          <.link navigate={~p"/"} class="bac-btn bac-btn-ghost bac-btn-icon" title={t(@locale, @locale_version, "Zurück")}>
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <div class="flex-1 min-w-0 flex items-center gap-3">
            <div class="min-w-0">
              <h1 class="font-semibold text-base truncate">
                {@device.name || t(@locale, @locale_version, "Gerät %{id}", id: @device.instance)}
              </h1>
              <p class="bac-mono text-xs bac-text-faint">{Address.format_device_address(@device)}</p>
            </div>
            <.link
              navigate={DeviceUrl.device_object_path(@device_id, @device, device_tab_opts(assigns))}
              class="bac-btn bac-btn-ghost bac-btn-sm shrink-0"
              title={t(@locale, @locale_version, "Geräteobjekt öffnen")}
              id="open-device-object"
            >
              <.icon name={ObjectTypeIcon.name(:device)} class="size-4" />
              <span class="hidden lg:inline">
                {t(@locale, @locale_version, "Geräteobjekt")}
              </span>
            </.link>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <DeviceServicesMenu.trigger
              device_id={@device_id}
              menu={@device_service_menu}
              locale={@locale}
              locale_version={@locale_version}
            />
            <button
              type="button"
              phx-click="subscribe_all_pv"
              disabled={@bulk_subscribing || @loading}
              class="bac-btn bac-btn-primary bac-btn-sm hidden md:inline-flex"
            >
              {t(@locale, @locale_version, "Alle PV abonnieren")}
            </button>
            <button
              type="button"
              phx-click="refresh_device"
              id="device-refresh-btn"
              disabled={@loading}
              class={["bac-btn bac-btn-ghost bac-btn-sm", @loading && "opacity-80"]}
              title={t(@locale, @locale_version, "Aktualisieren")}
              aria-busy={to_string(@loading)}
            >
              <.icon
                name="hero-arrow-path"
                class={
                  if(@loading,
                    do: "size-4 animate-spin text-[var(--bac-accent)]",
                    else: "size-4"
                  )
                }
              />
            </button>
          </div>
        </header>

        <div :if={@bulk_subscribing} class="px-5 pt-3">
          <progress
            class="bac-progress"
            value={@bulk_progress.done}
            max={max(@bulk_progress.total, 1)}
          >
          </progress>
          <p class="text-xs bac-text-faint mt-1.5">
            {t(@locale, @locale_version, "%{done} / %{total}", done: @bulk_progress.done, total: @bulk_progress.total)}
          </p>
        </div>

        <div class="px-5 pt-3">
          <div class="bac-tabs">
            <.link
              patch={device_tab_path(@device_id, "hierarchy", search: @search, types: @type_filter, status: @status_filter, sort: @sort_by, dir: @sort_dir)}
              class={["bac-tab", @tab == "hierarchy" && "bac-tab-active"]}
              id="device-tab-hierarchy"
            >
              <.icon name="hero-folder" class="size-4" />
              {t(@locale, @locale_version, "Hierarchie")}
            </.link>
            <.link
              patch={device_tab_path(@device_id, "objects", search: @search, types: @type_filter, status: @status_filter, sort: @sort_by, dir: @sort_dir)}
              class={["bac-tab", @tab == "objects" && "bac-tab-active"]}
              id="device-tab-objects"
            >
              <.icon name="hero-table-cells" class="size-4" />
              {t(@locale, @locale_version, "Objekte")}
            </.link>
            <.link
              patch={device_tab_path(@device_id, "subscriptions", device_tab_opts(assigns))}
              class={["bac-tab", @tab == "subscriptions" && "bac-tab-active"]}
              id="device-tab-subscriptions"
            >
              <.icon name="hero-signal" class="size-4" />
              {t(@locale, @locale_version, "COV")}
              <span :if={@cov_count > 0} class="bac-badge bac-badge-sm bac-badge-success">
                {@cov_count}
              </span>
            </.link>
            <.link
              patch={device_tab_path(@device_id, "alarms", device_tab_opts(assigns))}
              class={["bac-tab", @tab == "alarms" && "bac-tab-active"]}
              id="device-tab-alarms"
            >
              <.icon name="hero-bell-alert" class="size-4" />
              {t(@locale, @locale_version, "Alarme")}
              <span :if={@alarm_tab_count > 0} class="bac-badge bac-badge-sm bac-badge-error">
                {@alarm_tab_count}
              </span>
            </.link>
          </div>
        </div>

        <DeviceLoadProgress.status_banner
          :if={@loading}
          progress={@load_progress}
          locale={@locale}
          locale_version={@locale_version}
        />

        <DeviceScanRecovery.recovery_panel
          :if={!@loading}
          scan_errors={Map.get(@device, :scan_errors, [])}
          scan_retrying={@scan_retrying}
          locale={@locale}
          locale_version={@locale_version}
        />

        <div class="flex flex-1 min-h-0">
          <section class="flex-1 min-w-0 p-5 overflow-auto w-full">
            <ObjectSelectionBar.selection_bar
              :if={
                !@loading && @tab in ["hierarchy", "objects"] &&
                  MapSet.size(@selected_object_keys) > 0
              }
              count={MapSet.size(@selected_object_keys)}
              locale={@locale}
              locale_version={@locale_version}
            />

            <SubscriptionSelectionBar.selection_bar
              :if={
                !@loading && @tab == "subscriptions" && @cov_view == "subscriptions" &&
                  MapSet.size(@selected_subscription_keys) > 0
              }
              count={MapSet.size(@selected_subscription_keys)}
              locale={@locale}
              locale_version={@locale_version}
            />

            <HierarchyPanel.hierarchy_panel
              :if={!@loading && @tab == "hierarchy"}
              hierarchy_view={@hierarchy_view}
              hierarchy_view_paths={hierarchy_view_paths(@device_id, device_tab_opts(assigns))}
              hierarchy_root_path={@hierarchy_root_path}
              hierarchy_path_links={@hierarchy_path_links}
              hierarchy_source={@hierarchy_source}
              hierarchy_split={@hierarchy_split}
              name_hierarchy_form_open={@name_hierarchy_form_open}
              structured_hierarchy?={structured_hierarchy?(@sv_hierarchy)}
              device_id={@device_id}
              roots={@hierarchy.roots}
              entries={@hierarchy_entries}
              empty_hierarchy?={@hierarchy.empty?}
              tree_roots={@tree_roots}
              tree_expanded={@tree_expanded}
              tree_search={@tree_search}
              tree_match_count={@tree_match_count}
              explorer_search={@explorer_search}
              explorer_match_count={@explorer_match_count}
              list_opts={device_tab_opts(assigns)}
              selected_keys={@selected_object_keys}
              selectable_keys={@selectable_object_keys}
              subscribed_keys={@subscribed_keys}
              flash_cells={@flash_cells}
              locale={@locale}
              locale_version={@locale_version}
            />

            <ObjectTable.object_table
              :if={!@loading && @tab == "objects"}
              device_id={@device_id}
              objects={@objects}
              search={@search}
              type_filter={@type_filter}
              type_filter_open={@type_filter_open}
              status_filter={@status_filter}
              status_filter_open={@status_filter_open}
              sort_by={@sort_by}
              sort_dir={@sort_dir}
              subscribed_keys={@subscribed_keys}
              selected_keys={@selected_object_keys}
              flash_cells={@flash_cells}
              locale={@locale}
              locale_version={@locale_version}
            />

            <SubscriptionsPanel.subscriptions_panel
              :if={!@loading && @tab == "subscriptions"}
              device_id={@device_id}
              list_opts={device_tab_opts(assigns)}
              cov_view={@cov_view}
              cov_view_paths={cov_view_paths(@device_id, device_tab_opts(assigns))}
              subscriptions={@subscriptions}
              objects={@objects}
              cov_notifications={@cov_notifications}
              selected_keys={@selected_subscription_keys}
              sort_by={@subscriptions_sort_by}
              sort_dir={@subscriptions_sort_dir}
              notifications_sort_by={@cov_notifications_sort_by}
              notifications_sort_dir={@cov_notifications_sort_dir}
              locale={@locale}
              locale_version={@locale_version}
            />

            <AlarmsPanel.alarms_panel
              :if={!@loading && @tab == "alarms"}
              alarm_view={@alarm_view}
              device_id={@device_id}
              list_opts={device_tab_opts(assigns)}
              alarm_view_paths={alarm_view_paths(@device_id, device_tab_opts(assigns))}
              events={@events}
              notifications={@notifications}
              objects={@objects}
              active_alarm_objects={@active_alarm_objects}
              summary={@alarm_summary}
              refreshing={@alarms_refreshing}
              nc_subscribing={@nc_subscribing}
              nc_progress={@nc_progress}
              nc_enrolled_count={@nc_enrolled_count}
              nc_total={@nc_total}
              alarm_events_sort_by={@alarm_events_sort_by}
              alarm_events_sort_dir={@alarm_events_sort_dir}
              active_alarms_sort_by={@active_alarms_sort_by}
              active_alarms_sort_dir={@active_alarms_sort_dir}
              alarm_notifications_sort_by={@alarm_notifications_sort_by}
              alarm_notifications_sort_dir={@alarm_notifications_sort_dir}
              locale={@locale}
              locale_version={@locale_version}
            />
          </section>
        </div>

        <footer class="bac-footer">
          <span>
            {t(@locale, @locale_version, "%{count} Objekte", count: length(@objects))}
            <span :if={@hierarchy.structured_view_count > 0}>
              · {t(@locale, @locale_version, "%{count} Strukturansichten", count: @hierarchy.structured_view_count)}
            </span>
            <span :if={@cov_count > 0}>
              · {t(@locale, @locale_version, "%{count} COV aktiv", count: @cov_count)}
            </span>
            <span :if={@alarm_tab_count > 0}>
              · {t(@locale, @locale_version, "%{count} aktive Alarme", count: @alarm_tab_count)}
            </span>
          </span>
        </footer>
      </div>

      <WritePresentValueModal.modal
        :if={@write_modal}
        object={@write_modal}
        write_priority={@write_priority}
        writing={@writing_present_value}
        locale={@locale}
        locale_version={@locale_version}
      />

      <CovNotificationChartModal.modal
        :if={@cov_chart_modal_open && @cov_chart_subscription}
        subscription={@cov_chart_subscription}
        object={@cov_chart_object}
        loading={@cov_chart_loading}
        error={@cov_chart_error}
        start_value={@cov_chart_start}
        end_value={@cov_chart_end}
        has_data={@cov_chart_has_data}
        record_count={@cov_chart_record_count}
        locale={@locale}
        locale_version={@locale_version}
      />
      <% end %>
    </Layouts.app>

    <ActiveAlarmsPopup.active_alarms_panel
      open={@alarm_popup_open}
      entries={@active_alarm_entries}
      show_device={false}
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
end
