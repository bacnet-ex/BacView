defmodule BacViewWeb.ObjectLive do
  @moduledoc false
  use BacViewWeb, :live_view

  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PriorityArray

  alias BacView.BACnet.AlarmEvent
  alias BacView.BACnet.DeviceServices
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.FileTransfer
  alias BacView.BACnet.SubscriptionManager

  alias BacView.BACnet.Protocol.ComplexPropertyEditor
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.BACnet.Protocol.PropertyWriter
  alias BacView.BACnet.Protocol.StatusFlagsParser
  alias BacView.BACnet.Protocol.TrendLogChart
  alias BacView.BACnet.Protocol.TrendLogExport
  alias BacView.BACnet.Protocol.TrendLogNavigation
  alias BacView.BACnet.Protocol.TrendLogReader
  alias BacView.BACnet.Protocol.WeeklyScheduleEditor

  alias BacView.MapHelpers
  alias BacView.Text

  alias BacViewWeb.ActiveAlarmsAssigns
  alias BacViewWeb.ActiveAlarmsPopup
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.LiveFlash
  alias BacViewWeb.ObjectDetail
  alias BacViewWeb.StatusFlagsIcons
  alias BacViewWeb.TrendLogChartModal
  alias BacViewWeb.WriteFormParams
  alias BacViewWeb.WritePropertyModal
  alias BacViewWeb.WriteWeeklyScheduleModal

  @impl true
  def mount(
        %{"device_id" => device_id_str, "type" => type_str, "instance" => instance_str},
        _session,
        socket
      ) do
    device_id = String.to_integer(device_id_str)

    with {:ok, type_atom} <- parse_type(type_str),
         {instance_int, ""} <- Integer.parse(instance_str) do
      object_id = %ObjectIdentifier{type: type_atom, instance: instance_int}

      case Discovery.get_device(device_id) do
        {:ok, device} ->
          if connected?(socket) do
            Phoenix.PubSub.subscribe(BacView.PubSub, "device:#{device_id}:cov")
            Phoenix.PubSub.subscribe(BacView.PubSub, "device:#{device_id}:alarms")
            Phoenix.PubSub.subscribe(BacView.PubSub, "cov:updates")
            send(self(), :load_object)
          end

          {:ok,
           socket
           |> assign(:page_title, "#{type_atom}:#{instance_int}")
           |> assign(:device, device)
           |> assign(:device_id, device_id)
           |> assign(:object_id, object_id)
           |> assign(:object, nil)
           |> assign(:properties, [])
           |> assign(:loading, true)
           |> assign(:properties_loading, true)
           |> assign(:subscribed_keys, MapSet.new())
           |> assign(:write_priority, PropertyWriter.default_priority())
           |> assign(:writing_property, nil)
           |> assign(:write_property_modal, nil)
           |> assign(:show_shortcuts, false)
           |> assign(:return_tab, DeviceUrl.normalize_tab(nil))
           |> assign(:return_alarm_view, DeviceUrl.normalize_alarm_view(nil))
           |> assign(:return_cov_view, DeviceUrl.normalize_cov_view(nil))
           |> assign(:return_hierarchy_view, DeviceUrl.normalize_hierarchy_view(nil))
           |> assign(:return_hierarchy_path, [])
           |> assign(:objects_search, "")
           |> assign(:objects_type_filter, [])
           |> assign(:objects_status_filter, [])
           |> assign(:objects_sort_by, nil)
           |> assign(:objects_sort_dir, :asc)
           |> assign(:properties_sort_by, nil)
           |> assign(:properties_sort_dir, :asc)
           |> assign(:trend_chart_modal_open, false)
           |> assign(:trend_chart_loading, false)
           |> assign(:trend_chart_error, nil)
           |> assign(:trend_chart_start, "")
           |> assign(:trend_chart_end, "")
           |> assign(:trend_chart_data, nil)
           |> assign(:trend_chart_all_records, [])
           |> assign(:trend_chart_has_data, false)
           |> assign(:trend_chart_record_count, 0)
           |> assign(:device_objects, cached_device_objects(device_id))
           |> assign(:object_nav_targets, [])
           |> assign(:object_nav_menu_open, false)
           |> assign(:alarm_tab_count, 0)
           |> assign(:alarm_summary, %{
             active_count: 0,
             unacknowledged_count: 0,
             highest_priority: nil
           })
           |> assign(:file_metadata, %{stream_access: true, file_size: nil, read_only: false})
           |> assign(:file_content, nil)
           |> assign(:file_transfer_busy, false)
           |> allow_upload(:bac_file_upload,
             accept: :any,
             max_entries: 1,
             max_file_size: 50_000_000,
             auto_upload: true
           )
           |> ActiveAlarmsAssigns.init()
           |> refresh_cov_state()
           |> refresh_alarm_state()}

        :error ->
          {:ok,
           socket
           |> put_flash(:error, gt("Gerät nicht gefunden."))
           |> push_navigate(to: ~p"/")}
      end
    else
      _mount ->
        {:ok,
         socket
         |> put_flash(:error, gt("Ungültige Objekt-ID."))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:return_tab, DeviceUrl.normalize_tab(Map.get(params, "tab")))
     |> assign(:return_alarm_view, DeviceUrl.normalize_alarm_view(Map.get(params, "alarm_view")))
     |> assign(:return_cov_view, DeviceUrl.normalize_cov_view(Map.get(params, "cov_view")))
     |> assign(
       :return_hierarchy_view,
       DeviceUrl.normalize_hierarchy_view(Map.get(params, "hierarchy_view"))
     )
     |> assign(
       :return_hierarchy_path,
       DeviceUrl.normalize_hierarchy_path(Map.get(params, "h_path"))
     )
     |> assign(:objects_search, DeviceUrl.normalize_search(params["search"]))
     |> assign(:objects_type_filter, DeviceUrl.normalize_types(params["types"]))
     |> assign(:objects_status_filter, DeviceUrl.normalize_status(params["status"]))
     |> assign(:objects_sort_by, DeviceUrl.normalize_sort_column(params["sort"]))
     |> assign(:objects_sort_dir, DeviceUrl.normalize_sort_dir(params["dir"]))}
  end

  @impl true
  def handle_info(:load_object, socket) do
    parent = self()
    device_id = socket.assigns.device_id
    object_id = socket.assigns.object_id

    Task.start(fn ->
      device_result = DeviceSession.load(device_id)
      props_result = DeviceSession.read_properties(device_id, object_id)
      send(parent, {:object_load_done, device_result, props_result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:object_load_done, device_result, props_result}, socket) do
    object =
      case device_result do
        {:ok, loaded} ->
          Enum.find(loaded.objects, fn obj ->
            obj.type == socket.assigns.object_id.type and
              obj.instance == socket.assigns.object_id.instance
          end)

        _load_object ->
          nil
      end

    object = refresh_object_from_properties(object, props_result)

    {properties, properties_loading} =
      case props_result do
        {:ok, properties} -> {PropertyWriter.enrich_properties(properties, object), false}
        {:error, _load_object} -> {[], false}
      end

    page_title =
      cond do
        object && object.name -> object.name
        object -> "#{object.type}:#{object.instance}"
        true -> socket.assigns.page_title
      end

    device_objects =
      case device_result do
        {:ok, loaded} -> loaded.objects
        _load_object -> socket.assigns.device_objects
      end

    file_metadata =
      if object && object.type == :file do
        FileTransfer.file_metadata(properties)
      else
        socket.assigns.file_metadata
      end

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:object, Text.sanitize_object(object))
      |> assign(:properties, properties)
      |> assign(:properties_loading, properties_loading)
      |> assign(:page_title, page_title)
      |> assign(:device_objects, device_objects)
      |> assign(:file_metadata, file_metadata)
      |> assign(:file_content, nil)
      |> assign_object_nav_targets(object, properties, device_objects)
      |> maybe_refresh_object_summary(properties, object)
      |> refresh_alarm_state()

    socket =
      case props_result do
        {:error, reason} ->
          LiveFlash.put_error(socket, :load_properties, reason)

        _load_object ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:file_read_complete, {:ok, %{data: data}}}, socket) do
    object = socket.assigns.object
    view = FileTransfer.content_view(data)

    file_content = %{
      data: data,
      filename: FileTransfer.download_filename(object.type, object.instance, view.printable),
      mime: FileTransfer.content_mime(view.printable),
      printable: view.printable,
      preview: view.preview,
      truncated: view.truncated,
      size: view.size
    }

    {:noreply,
     socket
     |> assign(:file_transfer_busy, false)
     |> assign(:file_content, file_content)
     |> put_flash(:info, gt("Datei erfolgreich gelesen."))}
  end

  def handle_info({:file_read_complete, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:file_transfer_busy, false)
     |> LiveFlash.put_error(:atomic_read_file, reason)}
  end

  def handle_info({:file_write_complete, :ok}, socket) do
    {:noreply,
     socket
     |> assign(:file_transfer_busy, false)
     |> put_flash(:info, gt("Datei erfolgreich geschrieben."))}
  end

  def handle_info({:file_write_complete, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:file_transfer_busy, false)
     |> LiveFlash.put_error(:atomic_write_file, reason)}
  end

  @impl true
  def handle_info(:load_trend_chart, socket) do
    if socket.assigns.trend_chart_modal_open do
      parent = self()
      device_id = socket.assigns.device_id
      object_id = socket.assigns.object_id
      start_value = socket.assigns.trend_chart_start
      end_value = socket.assigns.trend_chart_end
      properties = socket.assigns.properties
      device_objects = socket.assigns.device_objects
      all_records = socket.assigns.trend_chart_all_records

      Task.start(fn ->
        result =
          load_trend_chart_data(
            device_id,
            object_id,
            start_value,
            end_value,
            properties,
            device_objects,
            all_records
          )

        send(parent, {:trend_chart_loaded, result})
      end)

      {:noreply, assign(socket, :trend_chart_loading, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:trend_chart_loaded, result}, socket) do
    socket = assign(socket, :trend_chart_loading, false)

    case result do
      {:ok,
       %{
         data: data,
         records: records,
         all_records: all_records,
         start_dt: start_dt,
         end_dt: end_dt
       }} ->
        {:noreply,
         socket
         |> assign(:trend_chart_data, data)
         |> assign(:trend_chart_all_records, all_records)
         |> assign(:trend_chart_start, TrendLogChart.to_form_value(start_dt))
         |> assign(:trend_chart_end, TrendLogChart.to_form_value(end_dt))
         |> assign(:trend_chart_has_data, chart_has_data?(data))
         |> assign(:trend_chart_record_count, length(records))
         |> assign(:trend_chart_error, nil)
         |> push_event("trend-chart:update", trend_chart_event_payload(data))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:trend_chart_data, nil)
         |> assign(:trend_chart_has_data, false)
         |> assign(:trend_chart_record_count, 0)
         |> assign(:trend_chart_error, ErrorMessage.format_reason(reason))
         |> push_event("trend-chart:update", %{series: [], scales: [], empty_label: nil})}
    end
  end

  @impl true
  def handle_info({:cov_update, update}, socket) do
    object = socket.assigns.object

    socket =
      if (object && object.type == update.type) and object.instance == update.instance do
        case update.property do
          :present_value ->
            present_prop = find_property(socket.assigns.properties, :present_value)
            coerced = PropertyFormatter.coerce_present_value(update.value, object, present_prop)

            socket
            |> assign(
              :object,
              MapHelpers.update(object, %{
                present_value: coerced,
                present_value_formatted:
                  PropertyFormatter.format_present_value(coerced, object, present_prop),
                updated_at: update.at
              })
            )
            |> update_present_value_property(Map.put(update, :value, coerced))

          :status_flags ->
            flags = StatusFlagsParser.normalize(update.value)

            socket
            |> assign(
              :object,
              MapHelpers.update(object, %{status_flags: flags, updated_at: update.at})
            )
            |> update_property_row(:status_flags, flags, update.at)
            |> sync_device_object_flags(object, flags, update.at)

          _load_object ->
            socket
        end
      else
        socket
      end

    {:noreply, refresh_alarm_state(socket)}
  end

  @impl true
  def handle_info(:alarms_updated, socket) do
    {:noreply, refresh_alarm_popup(refresh_alarm_state(socket))}
  end

  @impl true
  def handle_info({:cov_notification, _entry}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:cov_updated, socket) do
    {:noreply, refresh_cov_state(socket)}
  end

  @impl true
  def handle_info(:refresh_properties, socket) do
    {:noreply, start_properties_refresh(socket)}
  end

  @impl true
  def handle_info({:properties_refreshed, result}, socket) do
    socket =
      case result do
        {:ok, properties} ->
          object =
            refresh_object_from_properties(socket.assigns.object, {:ok, properties})

          enriched = PropertyWriter.enrich_properties(properties, object)

          socket
          |> assign(:object, Text.sanitize_object(object))
          |> assign(:properties, enriched)
          |> assign(:properties_loading, false)
          |> assign(:writing_property, nil)
          |> assign_object_nav_targets(object, enriched, socket.assigns.device_objects)
          |> maybe_refresh_object_summary(enriched, object)
          |> maybe_refresh_file_metadata(object, enriched)

        {:error, reason} ->
          socket
          |> assign(:properties_loading, false)
          |> assign(:writing_property, nil)
          |> LiveFlash.put_error(:refresh_properties, reason)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_properties", _params, socket) do
    {:noreply, start_properties_refresh(socket)}
  end

  @impl true
  def handle_event("toggle_object_nav_menu", _params, socket) do
    {:noreply, assign(socket, :object_nav_menu_open, !socket.assigns.object_nav_menu_open)}
  end

  @impl true
  def handle_event("close_object_nav_menu", _params, socket) do
    {:noreply, assign(socket, :object_nav_menu_open, false)}
  end

  @impl true
  def handle_event("open_write_property_modal", %{"property" => property_name}, socket) do
    with {:ok, property} <- parse_property(property_name),
         %{} = prop <- find_property(socket.assigns.properties, property) do
      {:noreply, assign(socket, :write_property_modal, build_write_property_modal(socket, prop))}
    else
      {:error, reason} ->
        {:noreply, write_error(socket, reason)}

      _handle_event ->
        {:noreply, put_flash(socket, :error, gt("Eigenschaft nicht gefunden."))}
    end
  end

  @impl true
  def handle_event("close_write_property_modal", _params, socket) do
    {:noreply, assign(socket, :write_property_modal, nil)}
  end

  @impl true
  def handle_event("weekly_schedule_select_day", %{"day" => day}, socket) do
    case socket.assigns.write_property_modal do
      %{editor: :weekly_schedule} = modal ->
        {:noreply,
         assign(socket, :write_property_modal, %{
           modal
           | active_day: String.to_integer(day)
         })}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_weekly_schedule", %{"entries" => entries}, socket) do
    case socket.assigns.write_property_modal do
      %{editor: :weekly_schedule} = modal ->
        update_weekly_schedule_day(socket, modal, entries)

      _handle_event ->
        {:noreply, socket}
    end
  end

  def handle_event("change_weekly_schedule", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("weekly_schedule_add_entry", _params, socket) do
    case socket.assigns.write_property_modal do
      %{editor: :weekly_schedule, draft: draft, active_day: active_day, value_kind: value_kind} =
          modal ->
        updated_draft = %{
          draft
          | days:
              Enum.map(WeeklyScheduleEditor.draft_days(draft), fn day ->
                if day.index == active_day,
                  do: WeeklyScheduleEditor.add_entry(day, value_kind),
                  else: day
              end)
        }

        {:noreply,
         assign(socket, :write_property_modal, %{
           modal
           | draft: updated_draft,
             field_error: nil,
             submit_error: nil
         })}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("weekly_schedule_remove_entry", %{"entry_id" => entry_id}, socket) do
    case socket.assigns.write_property_modal do
      %{editor: :weekly_schedule, draft: draft, active_day: active_day} = modal ->
        updated_draft = %{
          draft
          | days:
              Enum.map(WeeklyScheduleEditor.draft_days(draft), fn day ->
                if day.index == active_day,
                  do: WeeklyScheduleEditor.remove_entry(day, entry_id),
                  else: day
              end)
        }

        {:noreply,
         assign(socket, :write_property_modal, %{
           modal
           | draft: updated_draft,
             field_error: nil,
             submit_error: nil
         })}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_weekly_schedule_mode", %{"mode" => mode}, socket) do
    target_mode = if mode == "json", do: :json, else: :weekdays

    case socket.assigns.write_property_modal do
      %{editor: :weekly_schedule, property: prop} = modal ->
        updated_modal =
          case target_mode do
            :json ->
              case weekly_schedule_to_json(modal) do
                {:ok, json} ->
                  %{
                    modal
                    | mode: :json,
                      draft_json: json,
                      json_error: nil,
                      field_error: nil
                  }

                {:error, reason} ->
                  %{modal | mode: :weekdays, field_error: format_editor_error(reason)}
              end

            :weekdays ->
              case weekly_schedule_from_json(modal, prop) do
                {:ok, draft} ->
                  %{
                    modal
                    | mode: :weekdays,
                      draft: draft,
                      field_error: nil,
                      json_error: nil
                  }

                {:error, reason} ->
                  %{modal | json_error: format_editor_error(reason)}
              end
          end

        {:noreply, assign(socket, :write_property_modal, updated_modal)}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_weekly_schedule_json", %{"json" => json}, socket) do
    case socket.assigns.write_property_modal do
      %{editor: :weekly_schedule, property: prop} = modal ->
        json_error =
          case WeeklyScheduleEditor.decode_json(json, prop.value) do
            {:ok, _handle_event} -> nil
            {:error, %Jason.DecodeError{}} -> gt("Ungültiges JSON.")
            {:error, reason} -> format_editor_error(reason)
          end

        {:noreply,
         assign(socket, :write_property_modal, %{
           modal
           | draft_json: json,
             json_error: json_error,
             submit_error: nil
         })}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_write_property_fields", %{"field" => fields}, socket) do
    case socket.assigns.write_property_modal do
      %{property: prop} = modal ->
        fields =
          modal.draft_fields
          |> Map.merge(ComplexPropertyEditor.normalize_field_params(fields))
          |> clear_tag_number_for_primitive_encoding()

        field_error =
          case ComplexPropertyEditor.apply_form_fields(%{"field" => fields}, prop.value) do
            {:ok, _handle_event} -> nil
            {:error, reason} -> format_editor_error(reason)
          end

        {:noreply,
         assign(socket, :write_property_modal, %{
           modal
           | draft_fields: fields,
             field_error: field_error,
             submit_error: nil
         })}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_write_property_json", %{"json" => json}, socket) do
    case socket.assigns.write_property_modal do
      %{property: prop} = modal ->
        json_error =
          case ComplexPropertyEditor.decode_json(json, prop.value) do
            {:ok, _handle_event} -> nil
            {:error, %Jason.DecodeError{}} -> gt("Ungültiges JSON.")
            {:error, reason} -> format_editor_error(reason)
          end

        {:noreply,
         assign(socket, :write_property_modal, %{
           modal
           | draft_json: json,
             json_error: json_error,
             submit_error: nil
         })}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_write_property_editor", %{"mode" => mode}, socket) do
    editor_mode = if mode == "json", do: :json, else: :fields

    case socket.assigns.write_property_modal do
      %{property: prop} = modal ->
        modal =
          case editor_mode do
            :json ->
              case ComplexPropertyEditor.apply_form_fields(
                     %{"field" => modal.draft_fields},
                     prop.value
                   ) do
                {:ok, struct} ->
                  case ComplexPropertyEditor.encode_json(struct) do
                    {:ok, json} ->
                      %{modal | draft_json: json, json_error: nil, field_error: nil}

                    {:error, reason} ->
                      %{modal | field_error: format_editor_error(reason)}
                  end

                {:error, reason} ->
                  %{modal | field_error: format_editor_error(reason)}
              end

            :fields ->
              form_fields = ComplexPropertyEditor.form_fields(prop.value)

              %{
                modal
                | form_fields: form_fields,
                  draft_fields: ComplexPropertyEditor.initial_field_params(form_fields),
                  field_error: nil,
                  json_error: nil
              }
          end

        {:noreply, assign(socket, :write_property_modal, %{modal | editor_mode: editor_mode})}

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("write_property_modal", _params, socket) do
    case socket.assigns.write_property_modal do
      %{property: prop} = modal ->
        priority = socket.assigns.write_priority

        with {:ok, property} <- parse_property(prop.property),
             {:ok, parsed} <- decode_write_property_modal(modal),
             {:ok, socket} <- do_write_property(socket, property, parsed, priority) do
          {:noreply, assign(socket, :write_property_modal, nil)}
        else
          {:error, :empty_value} ->
            {:noreply, put_modal_submit_error(socket, gt("Bitte einen Wert eingeben."))}

          {:error, :invalid_atom} ->
            {:noreply, put_modal_submit_error(socket, gt("Ungültiger Enum-Wert im JSON."))}

          {:error, %Jason.DecodeError{}} ->
            {:noreply, put_modal_submit_error(socket, gt("Ungültiges JSON."))}

          {:error, {:write_failed, reason}} ->
            {:noreply, modal_action_failed(socket, :write_property, reason)}

          {:error, {:read_back_failed, reason}} ->
            {:noreply, modal_action_failed(socket, :read_back_property, reason)}

          {:error, {:verify_mismatch, property, _written, read}} ->
            {:noreply, modal_verify_mismatch(socket, property, read)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:writing_property, nil)
             |> put_modal_submit_error(
               gt("Ungültiger Wert: %{reason}", reason: format_parse_error(reason))
             )}
        end

      _handle_event ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_write_priority", %{"priority" => priority}, socket) do
    case Integer.parse(priority) do
      {p, ""} when p in 1..16 -> {:noreply, assign(socket, :write_priority, p)}
      _handle_event -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("write_property", params, socket) do
    form_params = WriteFormParams.normalize(params)
    property_name = form_params["property"]
    priority = WriteFormParams.priority(params, socket.assigns.write_priority)

    with {:ok, property} <- parse_property(property_name),
         prop <- find_property(socket.assigns.properties, property),
         {:ok, parsed} <- PropertyWriter.parse_write_params(form_params, prop),
         {:ok, socket} <- do_write_property(socket, property, parsed, priority) do
      {:noreply, assign(socket, :write_priority, priority)}
    else
      {:error, :empty_value} ->
        {:noreply, put_flash(socket, :error, gt("Bitte einen Wert eingeben."))}

      {:error, {:write_failed, reason}} ->
        {:noreply, write_failed(socket, reason)}

      {:error, {:read_back_failed, reason}} ->
        {:noreply, read_back_failed(socket, reason)}

      {:error, {:verify_mismatch, property, _written, read}} ->
        {:noreply, verify_mismatch_property(socket, property, read)}

      {:error, :no_object} ->
        {:noreply, put_flash(socket, :error, gt("Objekt nicht geladen."))}

      {:error, reason} ->
        {:noreply, write_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("reset_property", params, socket) do
    property_name = params["property"]
    priority = WriteFormParams.priority(params, socket.assigns.write_priority)

    with {:ok, property} <- parse_property(property_name),
         {:ok, socket} <- do_write_property(socket, property, nil, priority) do
      {:noreply, assign(socket, :write_priority, priority)}
    else
      {:error, {:write_failed, reason}} ->
        {:noreply, write_failed(socket, reason)}

      {:error, {:read_back_failed, reason}} ->
        {:noreply, read_back_failed(socket, reason)}

      {:error, {:verify_mismatch, property, _written, read}} ->
        {:noreply, verify_mismatch_property(socket, property, read)}

      {:error, reason} ->
        {:noreply, write_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("open_trend_chart_modal", _params, socket) do
    socket =
      socket
      |> assign(:trend_chart_modal_open, true)
      |> assign(:trend_chart_loading, true)
      |> assign(:trend_chart_error, nil)
      |> assign(:trend_chart_start, "")
      |> assign(:trend_chart_end, "")
      |> assign(:trend_chart_data, nil)
      |> assign(:trend_chart_all_records, [])
      |> assign(:trend_chart_has_data, false)
      |> assign(:trend_chart_record_count, 0)

    send(self(), :load_trend_chart)
    {:noreply, socket}
  end

  def handle_event("download_file_content", _params, socket) do
    case socket.assigns.file_content do
      %{data: data, filename: filename, mime: mime} ->
        {:noreply,
         push_event(socket, "download_file", %{
           content: Base.encode64(data),
           filename: filename,
           mime: mime,
           encoding: "base64"
         })}

      _handle_event ->
        {:noreply, put_flash(socket, :error, gt("Keine Datei zum Herunterladen."))}
    end
  end

  def handle_event("read_file", _params, socket) do
    if file_object?(socket) do
      parent = self()
      device_id = socket.assigns.device_id
      object_id = socket.assigns.object_id
      metadata = socket.assigns.file_metadata

      Task.start(fn ->
        result =
          with {:ok, address} <- DeviceServices.device_address(device_id) do
            FileTransfer.read_file(address, object_id, stream_access: metadata.stream_access)
          end

        send(parent, {:file_read_complete, result})
      end)

      {:noreply, assign(socket, :file_transfer_busy, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_file_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("write_file", _params, socket) do
    if file_object?(socket) and not socket.assigns.file_metadata.read_only do
      parent = self()
      device_id = socket.assigns.device_id
      object_id = socket.assigns.object_id
      metadata = socket.assigns.file_metadata

      {:noreply,
       socket
       |> assign(:file_transfer_busy, true)
       |> consume_uploaded_entries(:bac_file_upload, fn %{path: path}, _entry ->
         data = File.read!(path)

         Task.start(fn ->
           result =
             with {:ok, address} <- DeviceServices.device_address(device_id) do
               FileTransfer.write_file(address, object_id, data,
                 stream_access: metadata.stream_access
               )
             end

           send(parent, {:file_write_complete, result})
         end)

         {:ok, :started}
       end)}
    else
      {:noreply, put_flash(socket, :error, gt("Datei kann nicht geschrieben werden."))}
    end
  end

  def handle_event("close_trend_chart_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:trend_chart_modal_open, false)
     |> assign(:trend_chart_loading, false)
     |> push_event("trend-chart:update", %{series: [], scales: [], empty_label: nil})}
  end

  def handle_event("trend_chart_change_range", params, socket) do
    {:noreply,
     socket
     |> assign(:trend_chart_start, Map.get(params, "start", socket.assigns.trend_chart_start))
     |> assign(:trend_chart_end, Map.get(params, "end", socket.assigns.trend_chart_end))}
  end

  def handle_event("trend_chart_load", params, socket) do
    socket =
      socket
      |> assign(:trend_chart_start, Map.get(params, "start", socket.assigns.trend_chart_start))
      |> assign(:trend_chart_end, Map.get(params, "end", socket.assigns.trend_chart_end))

    send(self(), :load_trend_chart)
    {:noreply, assign(socket, :trend_chart_loading, true)}
  end

  def handle_event("trend_chart_export_csv", _params, socket) do
    {:noreply, trend_chart_download(socket, :csv)}
  end

  def handle_event("trend_chart_export_json", _params, socket) do
    {:noreply, trend_chart_download(socket, :json)}
  end

  def handle_event("sort_properties", %{"column" => column}, socket) do
    case BacViewWeb.PropertyTable.normalize_sort_column(column) do
      nil ->
        {:noreply, socket}

      column ->
        {sort_by, sort_dir} =
          BacViewWeb.PropertyTable.toggle_sort(
            socket.assigns.properties_sort_by,
            socket.assigns.properties_sort_dir,
            column
          )

        {:noreply,
         socket
         |> assign(:properties_sort_by, sort_by)
         |> assign(:properties_sort_dir, sort_dir)}
    end
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
      _handle_event -> {:noreply, put_flash(socket, :error, gt("Ungültige Objekt-ID."))}
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
      _handle_event -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("global_keydown", params, socket) do
    key = Map.get(params, "key", "")

    cond do
      BacViewWeb.Shortcuts.go_up_pressed?(params) ->
        {:noreply, push_navigate(socket, to: device_return_path(socket))}

      BacViewWeb.Shortcuts.refresh_key?(key) ->
        {:noreply, start_properties_refresh(socket)}

      true ->
        BacViewWeb.Shortcuts.handle(params, socket, tabs: %{})
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
       objects: socket.assigns.device_objects
     )}
  end

  @impl true
  def handle_event("close_alarm_popup", _params, socket) do
    {:noreply, ActiveAlarmsAssigns.close(socket)}
  end

  defp update_present_value_property(socket, update) do
    object = socket.assigns.object
    value = update.value

    properties =
      Enum.map(socket.assigns.properties, fn prop ->
        if prop.property == :present_value do
          refresh_property_value(prop, value, object, update.at)
        else
          prop
        end
      end)

    assign(socket, :properties, properties)
  end

  defp update_property_row(socket, property, value, at \\ nil) do
    object = socket.assigns.object

    properties =
      Enum.map(socket.assigns.properties, fn prop ->
        if prop.property == property do
          refresh_property_value(prop, value, object, at)
        else
          prop
        end
      end)

    assign(socket, :properties, properties)
  end

  defp device_return_path(socket) do
    DeviceUrl.device_path(socket.assigns.device_id,
      tab: socket.assigns.return_tab,
      search: socket.assigns.objects_search,
      types: socket.assigns.objects_type_filter,
      status: socket.assigns.objects_status_filter,
      sort: socket.assigns.objects_sort_by,
      dir: socket.assigns.objects_sort_dir,
      alarm_view: socket.assigns.return_alarm_view,
      cov_view: socket.assigns.return_cov_view,
      hierarchy_view: socket.assigns.return_hierarchy_view,
      hierarchy_path: socket.assigns.return_hierarchy_path
    )
  end

  defp refresh_cov_state(socket) do
    subs = SubscriptionManager.list_active(socket.assigns.device_id)

    keys =
      subs
      |> Enum.map(fn sub ->
        {sub.object_id.type, sub.object_id.instance, sub.property}
      end)
      |> MapSet.new()

    assign(socket, :subscribed_keys, keys)
  end

  defp parse_type(type) when is_binary(type) do
    {:ok, String.to_existing_atom(type)}
  rescue
    ArgumentError -> :error
  end

  defp parse_property("present_value"), do: {:ok, :present_value}

  defp parse_property(prop) when is_atom(prop), do: {:ok, prop}

  defp parse_property(prop) when is_binary(prop) do
    cond do
      String.contains?(prop, ":") ->
        {:ok, prop}

      match?({_int, ""}, Integer.parse(prop)) ->
        {int, ""} = Integer.parse(prop)
        {:ok, int}

      true ->
        {:ok, String.to_existing_atom(prop)}
    end
  rescue
    ArgumentError -> {:ok, prop}
  end

  defp do_write_property(socket, property, value, priority) do
    object = socket.assigns.object
    object_id = socket.assigns.object_id
    device_id = socket.assigns.device_id

    if is_nil(object) do
      {:error, :no_object}
    else
      opts = PropertyWriter.write_opts(object, property, priority)

      socket = assign(socket, :writing_property, property)

      with :ok <- DeviceSession.write_property(device_id, object_id, property, value, opts),
           {:ok, read_result} <-
             read_back_property(device_id, object_id, property, value, object, priority) do
        message =
          if value == nil do
            gt("Priorität %{priority} zurückgesetzt (null).", priority: priority)
          else
            gt("Eigenschaft erfolgreich geschrieben.")
          end

        {:ok,
         socket
         |> assign(:writing_property, nil)
         |> apply_write_result(property, read_result)
         |> maybe_sync_status_flags_after_present_value_write(property)
         |> put_flash(:info, message)}
      else
        {:error, {:read_back_failed, _socket}} = err ->
          err

        {:error, {:verify_mismatch, _socket, _property, _value}} = err ->
          err

        {:error, reason} ->
          {:error, {:write_failed, reason}}
      end
    end
  end

  defp read_back_property(device_id, object_id, property, written_value, object, priority) do
    if PropertyWriter.priority_write?(object, property, priority) do
      read_back_priority_write(device_id, object_id, written_value, priority)
    else
      read_back_property(device_id, object_id, property, written_value)
    end
  end

  defp read_back_property(device_id, object_id, property, written_value) do
    case DeviceSession.read_property(device_id, object_id, property) do
      {:ok, read_value} ->
        if PropertyWriter.values_match?(written_value, read_value) do
          {:ok, read_value}
        else
          {:error, {:verify_mismatch, property, written_value, read_value}}
        end

      {:error, reason} ->
        {:error, {:read_back_failed, reason}}
    end
  end

  defp read_back_priority_write(device_id, object_id, written_value, priority) do
    case DeviceSession.read_property(device_id, object_id, :priority_array) do
      {:ok, priority_array} ->
        case PropertyWriter.normalize_priority_array(priority_array) do
          %PriorityArray{} = pa ->
            slot_value = PropertyWriter.priority_slot_value(pa, priority)

            if PropertyWriter.values_match?(written_value, slot_value) do
              {:ok, {:priority_array, pa}}
            else
              {:error, {:verify_mismatch, :present_value, written_value, slot_value}}
            end

          _device_id ->
            {:error, {:read_back_failed, :invalid_priority_array}}
        end

      {:error, reason} ->
        {:error, {:read_back_failed, reason}}
    end
  end

  defp apply_write_result(socket, :present_value, {:priority_array, priority_array}) do
    refresh_priority_state(socket, priority_array)
  end

  defp apply_write_result(socket, property, read_value) do
    apply_read_property(socket, property, read_value)
  end

  defp refresh_priority_state(socket, priority_array) do
    object = socket.assigns.object

    active_present_value =
      case PriorityArray.get_value(priority_array) do
        {_socket, value} -> value
        nil -> nil
      end

    object_for_priority =
      if object do
        object
        |> Map.put(:priority_array, priority_array)
        |> Map.put(:present_value, active_present_value)
        |> Map.put(
          :present_value_formatted,
          PropertyFormatter.format_present_value(active_present_value, object)
        )
        |> Map.merge(
          PropertyWriter.active_priority_info(Map.put(object, :priority_array, priority_array))
        )
      else
        object
      end

    properties =
      Enum.map(socket.assigns.properties, fn prop ->
        cond do
          prop.property == :priority_array ->
            refresh_property_value(prop, priority_array, object_for_priority || object)

          prop.property == :present_value ->
            refresh_property_value(prop, active_present_value, object_for_priority)

          true ->
            prop
        end
      end)

    socket =
      if object_for_priority do
        assign(socket, :object, object_for_priority)
      else
        socket
      end

    socket
    |> assign(:properties, properties)
    |> publish_present_value_write(active_present_value)
  end

  defp apply_read_property(socket, property, read_value) do
    properties =
      socket.assigns.properties
      |> Enum.map(fn prop ->
        if prop.property == property do
          refresh_property_value(prop, read_value, socket.assigns.object)
        else
          prop
        end
      end)
      |> PropertyReader.sync_input_present_value_writable(socket.assigns.object)

    socket =
      socket
      |> assign(:properties, properties)
      |> maybe_refresh_object_summary(properties, socket.assigns.object)

    if property == :present_value do
      publish_present_value_write(socket, read_value)
    else
      socket
    end
  end

  defp maybe_sync_status_flags_after_present_value_write(socket, :present_value) do
    device_id = socket.assigns.device_id
    object_id = socket.assigns.object_id

    case DeviceSession.read_property(device_id, object_id, :status_flags) do
      {:ok, flags} ->
        case StatusFlagsParser.normalize(flags) do
          nil ->
            socket

          normalized ->
            socket
            |> assign(
              :object,
              MapHelpers.update(socket.assigns.object, %{
                status_flags: normalized,
                updated_at: DateTime.utc_now()
              })
            )
            |> update_property_row(:status_flags, normalized)
            |> then(fn s ->
              DeviceSession.publish_property_update(
                device_id,
                object_id,
                :status_flags,
                normalized
              )

              s
            end)
        end

      _socket ->
        socket
    end
  end

  defp maybe_sync_status_flags_after_present_value_write(socket, _property), do: socket

  defp publish_present_value_write(socket, value) do
    object = socket.assigns.object
    present_prop = find_property(socket.assigns.properties, :present_value)
    coerced = PropertyFormatter.coerce_present_value(value, object, present_prop)

    DeviceSession.publish_property_update(
      socket.assigns.device_id,
      socket.assigns.object_id,
      :present_value,
      coerced
    )

    socket
  end

  defp write_error(socket, reason) do
    socket
    |> assign(:writing_property, nil)
    |> put_flash(
      :error,
      gt("Ungültiger Wert: %{reason}", reason: format_parse_error(reason))
    )
  end

  defp write_failed(socket, reason) do
    socket
    |> assign(:writing_property, nil)
    |> LiveFlash.put_error(:write_property, reason)
  end

  defp read_back_failed(socket, reason) do
    socket
    |> assign(:writing_property, nil)
    |> LiveFlash.put_error(:read_back_property, reason)
  end

  defp verify_mismatch_property(socket, property, read_value) do
    socket
    |> assign(:writing_property, nil)
    |> apply_read_property(property, read_value)
    |> put_flash(
      :error,
      gt(
        "Geschriebener Wert weicht vom gelesenen Wert ab: %{value}",
        value: PropertyFormatter.format_value(read_value, nil)
      )
    )
  end

  defp find_property(properties, property) do
    Enum.find(properties, &(&1.property == property))
  end

  defp refresh_object_from_properties(object, {:ok, properties}) when is_map(object) do
    DeviceSession.refresh_object_from_properties(object, properties)
  end

  defp refresh_object_from_properties(object, _result), do: object

  defp maybe_refresh_object_summary(socket, properties, object) when is_map(object) do
    assign(socket, :object, refresh_object_from_properties(object, {:ok, properties}))
  end

  defp maybe_refresh_object_summary(socket, _properties, _object), do: socket

  defp maybe_refresh_file_metadata(socket, %{type: :file}, properties) do
    socket
    |> assign(:file_metadata, FileTransfer.file_metadata(properties))
    |> assign(:file_content, nil)
  end

  defp maybe_refresh_file_metadata(socket, _object, _properties), do: socket

  defp start_properties_refresh(socket) do
    if socket.assigns.properties_loading do
      socket
    else
      parent = self()
      device_id = socket.assigns.device_id
      object_id = socket.assigns.object_id

      Task.start(fn ->
        result = DeviceSession.read_properties(device_id, object_id)
        send(parent, {:properties_refreshed, result})
      end)

      assign(socket, :properties_loading, true)
    end
  end

  defp format_parse_error(:invalid_boolean), do: gt("erwartet true/false")
  defp format_parse_error(:invalid_number), do: gt("erwartet Zahl")

  defp format_parse_error(:unsupported_struct),
    do: gt("Dieser Strukturtyp kann noch nicht geschrieben werden")

  defp format_parse_error(reason), do: inspect(reason)

  defp decode_write_property_modal(%{
         editor: :weekly_schedule,
         mode: :weekdays,
         draft: draft,
         value_kind: value_kind,
         property: prop
       }) do
    WeeklyScheduleEditor.to_bacnet(draft, prop.value, value_kind)
  end

  defp decode_write_property_modal(%{
         editor: :weekly_schedule,
         mode: :json,
         property: prop,
         draft_json: json
       }) do
    WeeklyScheduleEditor.decode_json(json, prop.value)
  end

  defp decode_write_property_modal(%{editor_mode: :fields, property: prop, draft_fields: fields}) do
    ComplexPropertyEditor.apply_form_fields(%{"field" => fields}, prop.value)
  end

  defp decode_write_property_modal(%{editor_mode: :json, property: prop, draft_json: json}) do
    ComplexPropertyEditor.decode_json(json, prop.value)
  end

  defp clear_tag_number_for_primitive_encoding(fields) do
    if Map.get(fields, "encoding") == "primitive" do
      Map.delete(fields, "extras.tag_number")
    else
      fields
    end
  end

  defp format_editor_error(:empty_value), do: gt("Bitte einen Wert eingeben.")
  defp format_editor_error(:invalid_boolean), do: gt("erwartet true/false")
  defp format_editor_error(:invalid_number), do: gt("erwartet Zahl")
  defp format_editor_error(:invalid_atom), do: gt("Ungültiger Enum-Wert.")
  defp format_editor_error(:invalid_enum), do: gt("Ungültiger Enum-Wert.")
  defp format_editor_error(:invalid_path), do: gt("Ungültiger Feldpfad.")
  defp format_editor_error(:invalid_json_value), do: gt("Ungültiger JSON-Wert.")
  defp format_editor_error(:invalid_struct_json), do: gt("Ungültige Struktur im JSON.")

  defp format_editor_error({:unknown_json_fields, keys}),
    do: gt("Unbekannte JSON-Felder: %{keys}", keys: Enum.join(keys, ", "))

  defp format_editor_error({:fixed_bacnet_array_size, expected, actual}),
    do:
      gt("Feste Array-Größe: %{expected} Elemente erforderlich (aktuell: %{actual}).",
        expected: expected,
        actual: actual
      )

  defp format_editor_error(:invalid_schedule_time),
    do: gt("Ungültige Zeit. Erwartet HH:MM, HH:MM:SS oder HH:MM:SS.hh (00:00–23:59:59.99).")

  defp format_editor_error(:invalid_schedule_value),
    do: gt("Ungültiger Wert für den geplanten Datentyp.")

  defp format_editor_error(:invalid_schedule_primitive_value),
    do:
      gt(
        "Wochenplan-Einträge erlauben nur primitive BACnet-Werte (z. B. REAL, BOOLEAN, ENUMERATED)."
      )

  defp format_editor_error(:missing_tag_number),
    do: gt("Tag-Nummer erforderlich für tagged/constructed Encodings.")

  defp format_editor_error(:invalid_encoding),
    do: gt("Ungültiges Encoding.")

  defp format_editor_error(reason), do: format_parse_error(reason)

  defp build_write_property_modal(socket, prop) do
    if WeeklyScheduleEditor.matches?(prop, socket.assigns.object) do
      value_kind = WeeklyScheduleEditor.infer_value_kind(socket.assigns.properties, prop.value)

      draft =
        prop.value
        |> WeeklyScheduleEditor.from_bacnet()
        |> WeeklyScheduleEditor.align_entry_value_kinds(value_kind)

      case WeeklyScheduleEditor.encode_json(prop.value) do
        {:ok, draft_json} ->
          %{
            editor: :weekly_schedule,
            property: prop,
            mode: :weekdays,
            active_day: 1,
            draft: draft,
            value_kind: value_kind,
            draft_json: draft_json,
            field_error: nil,
            json_error: nil,
            submit_error: nil
          }

        {:error, reason} ->
          %{
            editor: :weekly_schedule,
            property: prop,
            mode: :json,
            active_day: 1,
            draft: draft,
            value_kind: value_kind,
            draft_json: "",
            field_error: format_editor_error(reason),
            json_error: nil,
            submit_error: nil
          }
      end
    else
      build_generic_write_property_modal(prop)
    end
  end

  defp build_generic_write_property_modal(prop) do
    form_fields = ComplexPropertyEditor.form_fields(prop.value)

    case ComplexPropertyEditor.encode_json(prop.value) do
      {:ok, draft_json} ->
        %{
          editor: :generic,
          property: prop,
          editor_mode: :fields,
          form_fields: form_fields,
          draft_fields: ComplexPropertyEditor.initial_field_params(form_fields),
          draft_json: draft_json,
          field_error: nil,
          json_error: nil,
          submit_error: nil
        }

      {:error, reason} ->
        %{
          editor: :generic,
          property: prop,
          editor_mode: :json,
          form_fields: form_fields,
          draft_fields: ComplexPropertyEditor.initial_field_params(form_fields),
          draft_json: "",
          field_error: format_editor_error(reason),
          json_error: nil,
          submit_error: nil
        }
    end
  end

  defp update_weekly_schedule_day(socket, modal, entries) do
    %{draft: draft, active_day: active_day, value_kind: value_kind} = modal
    days = WeeklyScheduleEditor.draft_days(draft)

    {updated_days, field_error} =
      Enum.map_reduce(days, nil, fn day, err ->
        if day.index == active_day do
          case WeeklyScheduleEditor.apply_day_entries(day, entries, value_kind) do
            {:ok, updated} -> {updated, err}
            {:error, reason} -> {day, format_editor_error(reason)}
          end
        else
          {day, err}
        end
      end)

    {:noreply,
     assign(socket, :write_property_modal, %{
       modal
       | draft: %{draft | days: updated_days},
         field_error: field_error,
         submit_error: nil
     })}
  end

  defp weekly_schedule_to_json(%{draft: draft, value_kind: value_kind, property: prop}) do
    with {:ok, array} <- WeeklyScheduleEditor.to_bacnet(draft, prop.value, value_kind) do
      WeeklyScheduleEditor.encode_json(array)
    end
  end

  defp weekly_schedule_from_json(%{draft_json: json}, prop) do
    with {:ok, array} <- WeeklyScheduleEditor.decode_json(json, prop.value) do
      {:ok, WeeklyScheduleEditor.from_bacnet(array)}
    end
  end

  defp put_modal_submit_error(socket, message) do
    case socket.assigns.write_property_modal do
      %{} = modal ->
        assign(socket, :write_property_modal, Map.put(modal, :submit_error, message))

      _socket ->
        put_flash(socket, :error, message)
    end
  end

  defp modal_action_failed(socket, action, reason) do
    message = ErrorMessage.for_action(action, reason)
    detail = ErrorMessage.detail(reason)

    socket
    |> assign(:writing_property, nil)
    |> push_event("log_error", %{
      "action" => Atom.to_string(action),
      "message" => message,
      "detail" => detail
    })
    |> put_modal_submit_error(message)
  end

  defp modal_verify_mismatch(socket, property, read_value) do
    socket
    |> assign(:writing_property, nil)
    |> apply_read_property(property, read_value)
    |> put_modal_submit_error(
      gt(
        "Geschriebener Wert weicht vom gelesenen Wert ab: %{value}",
        value: PropertyFormatter.format_value(read_value, nil)
      )
    )
  end

  defp refresh_property_value(prop, value, object, at \\ nil) do
    value =
      if prop.property == :present_value do
        PropertyFormatter.coerce_present_value(value, object, prop)
      else
        value
      end

    display = PropertyDisplay.build(value)

    formatted = multistate_state_property_formatted(prop, value, object, display)

    display = Map.put(display, :formatted, formatted)

    refreshed =
      MapHelpers.update(prop, %{
        value: value,
        value_display: display,
        value_formatted: formatted,
        type:
          if(display.kind in [:struct, :priority_array, :array], do: "STRUCT", else: prop.type),
        updated_at: at || DateTime.utc_now()
      })

    if MultistateState.state_value_property?(refreshed.property) do
      case PropertyWriter.enrich_properties([refreshed], object) do
        [enriched | _rest] -> enriched
        _properties -> refreshed
      end
    else
      refreshed
    end
  end

  defp multistate_state_property_formatted(
         %{property: :present_value} = prop,
         value,
         object,
         _display
       ) do
    PropertyFormatter.format_present_value(value, object, prop)
  end

  defp multistate_state_property_formatted(
         %{property: :relinquish_default},
         value,
         object,
         display
       ) do
    if MultistateState.multistate_object?(object) do
      MultistateState.format_present_value(value, object) || display.formatted
    else
      display.formatted
    end
  end

  defp multistate_state_property_formatted(_prop, _value, _object, display), do: display.formatted

  defp refresh_alarm_popup(socket) do
    ActiveAlarmsAssigns.refresh(socket,
      device_id: socket.assigns.device_id,
      objects: socket.assigns.device_objects
    )
  end

  defp refresh_alarm_state(socket) do
    device_id = socket.assigns.device_id
    summary = AlarmEvent.summary(device_id)
    active_alarm_objects = active_alarm_objects(socket.assigns.device_objects)

    socket
    |> assign(:alarm_summary, summary)
    |> assign(:alarm_tab_count, alarm_tab_count(summary, active_alarm_objects))
  end

  defp active_alarm_objects(objects) when is_list(objects) do
    Enum.filter(objects, &object_in_active_alarm?/1)
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

  defp sync_device_object_flags(socket, object, flags, at) when is_map(object) do
    device_objects =
      Enum.map(socket.assigns.device_objects, fn obj ->
        if obj.type == object.type and obj.instance == object.instance do
          Map.merge(obj, %{status_flags: flags, updated_at: at})
        else
          obj
        end
      end)

    assign(socket, :device_objects, device_objects)
  end

  defp assign_object_nav_targets(socket, object, properties, device_objects) do
    targets =
      if object do
        TrendLogNavigation.targets_for_object(
          socket.assigns.device_id,
          object,
          device_objects,
          properties,
          device_instance(socket.assigns.device),
          object_nav_url_opts(socket)
        )
      else
        []
      end

    socket
    |> assign(:object_nav_targets, targets)
    |> assign(:object_nav_menu_open, false)
  end

  defp device_instance(%{instance: instance}) when is_integer(instance), do: instance
  defp device_instance(_device), do: nil

  defp object_nav_url_opts(socket) do
    [
      device_id: socket.assigns.device_id,
      tab: socket.assigns.return_tab,
      search: socket.assigns.objects_search,
      types: socket.assigns.objects_type_filter,
      status: socket.assigns.objects_status_filter,
      sort: socket.assigns.objects_sort_by,
      dir: socket.assigns.objects_sort_dir,
      alarm_view: socket.assigns.return_alarm_view,
      cov_view: socket.assigns.return_cov_view,
      hierarchy_view: socket.assigns.return_hierarchy_view,
      hierarchy_path: socket.assigns.return_hierarchy_path
    ]
  end

  defp cached_device_objects(device_id) do
    if :ets.whereis(:bacview_objects) == :undefined do
      []
    else
      case :ets.lookup(:bacview_objects, device_id) do
        [{^device_id, objects}] when is_list(objects) -> objects
        _device_id -> []
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      locale={@locale}
      locale_version={@locale_version}
      show_shortcuts={@show_shortcuts}
      shortcuts_context={:object}
    >
      <:topbar_end>
        <%= for _ <- [@locale_version] do %>
          <ActiveAlarmsPopup.active_alarms_badge
            count={@alarm_tab_count}
            open={@alarm_popup_open}
            locale={@locale}
            locale_version={@locale_version}
          />
        <% end %>
      </:topbar_end>

      <%= for _ <- [{@locale_version, @loading, @properties_loading}] do %>
        <ObjectDetail.object_detail
          device={@device}
          object={@object}
          properties={@properties}
          loading={@loading}
          properties_loading={@properties_loading}
          subscribed_keys={@subscribed_keys}
          write_priority={@write_priority}
          writing_property={@writing_property}
          return_tab={@return_tab}
          return_alarm_view={@return_alarm_view}
          return_cov_view={@return_cov_view}
          return_hierarchy_view={@return_hierarchy_view}
          return_hierarchy_path={@return_hierarchy_path}
          objects_search={@objects_search}
          objects_type_filter={@objects_type_filter}
          objects_status_filter={@objects_status_filter}
          objects_sort_by={@objects_sort_by}
          objects_sort_dir={@objects_sort_dir}
          object_nav_targets={@object_nav_targets}
          object_nav_menu_open={@object_nav_menu_open}
          properties_sort_by={@properties_sort_by}
          properties_sort_dir={@properties_sort_dir}
          file_metadata={@file_metadata}
          file_content={@file_content}
          file_transfer_busy={@file_transfer_busy}
          uploads={@uploads}
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

    <WriteWeeklyScheduleModal.modal
      :if={@write_property_modal && @object && @write_property_modal.editor == :weekly_schedule}
      object={@object}
      property={@write_property_modal.property}
      mode={@write_property_modal.mode}
      active_day={@write_property_modal.active_day}
      draft={@write_property_modal.draft}
      value_kind={@write_property_modal.value_kind}
      draft_json={@write_property_modal.draft_json}
      field_error={@write_property_modal.field_error}
      json_error={@write_property_modal.json_error}
      submit_error={@write_property_modal.submit_error}
      write_priority={@write_priority}
      writing={@writing_property == @write_property_modal.property.property}
      locale={@locale}
      locale_version={@locale_version}
    />

    <TrendLogChartModal.modal
      :if={@trend_chart_modal_open && @object}
      object={@object}
      loading={@trend_chart_loading}
      error={@trend_chart_error}
      start_value={@trend_chart_start}
      end_value={@trend_chart_end}
      has_data={@trend_chart_has_data}
      record_count={@trend_chart_record_count}
      locale={@locale}
      locale_version={@locale_version}
    />

    <WritePropertyModal.modal
      :if={@write_property_modal && @object && @write_property_modal.editor != :weekly_schedule}
      object={@object}
      property={@write_property_modal.property}
      editor_mode={@write_property_modal.editor_mode}
      form_fields={@write_property_modal.form_fields}
      draft_fields={@write_property_modal.draft_fields}
      draft_json={@write_property_modal.draft_json}
      field_error={@write_property_modal.field_error}
      json_error={@write_property_modal.json_error}
      submit_error={@write_property_modal.submit_error}
      write_priority={@write_priority}
      writing={@writing_property == @write_property_modal.property.property}
      locale={@locale}
      locale_version={@locale_version}
    />
    """
  end

  defp load_trend_chart_data(
         device_id,
         object_id,
         start_value,
         end_value,
         properties,
         device_objects,
         existing_records
       ) do
    with {:ok, all_records} <- fetch_trend_chart_records(device_id, object_id, existing_records),
         {:ok, filtered, start_dt, end_dt} <-
           select_trend_chart_records(all_records, start_value, end_value) do
      refs = TrendLogChart.property_refs_from_properties(properties)
      units = trend_log_units(properties)

      data =
        TrendLogChart.build(filtered, object_id,
          property_refs: refs,
          device_objects: device_objects,
          object_units: units,
          start_dt: start_dt,
          end_dt: end_dt
        )

      {:ok,
       %{
         data: data,
         records: filtered,
         all_records: all_records,
         start_dt: start_dt,
         end_dt: end_dt
       }}
    end
  end

  defp fetch_trend_chart_records(_device_id, _object_id, records) when records != [],
    do: {:ok, records}

  defp fetch_trend_chart_records(device_id, object_id, _device_id),
    do: TrendLogReader.fetch_all(device_id, object_id)

  defp select_trend_chart_records(all_records, start_value, end_value) do
    if blank_trend_chart_range?(start_value) and blank_trend_chart_range?(end_value) do
      {start_dt, end_dt} = TrendLogChart.range_from_records(all_records)
      filtered = TrendLogReader.records_for_range(all_records, :all)
      {:ok, filtered, start_dt, end_dt}
    else
      with {:ok, start_dt} <- parse_trend_chart_range(start_value, :start),
           {:ok, end_dt} <- parse_trend_chart_range(end_value, :end),
           :ok <- validate_trend_chart_range(start_dt, end_dt) do
        filtered = TrendLogReader.records_for_range(all_records, {start_dt, end_dt})
        {:ok, filtered, start_dt, end_dt}
      end
    end
  end

  defp blank_trend_chart_range?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_trend_chart_range?(_value), do: true

  defp parse_trend_chart_range(value, _fallback) when is_binary(value) do
    case TrendLogChart.parse_form_value(value) do
      {:ok, dt} -> {:ok, dt}
      :error -> {:error, :invalid_datetime_range}
    end
  end

  defp parse_trend_chart_range(_value2, _value), do: {:error, :invalid_datetime_range}

  defp parse_trend_chart_datetime(value) when is_binary(value) do
    case TrendLogChart.parse_form_value(value) do
      {:ok, dt} -> dt
      :error -> nil
    end
  end

  defp parse_trend_chart_datetime(_value), do: nil

  defp validate_trend_chart_range(start_dt, end_dt) do
    if NaiveDateTime.compare(start_dt, end_dt) == :gt do
      {:error, :invalid_datetime_range}
    else
      :ok
    end
  end

  defp trend_log_units(properties) do
    case Enum.find(properties, &(&1.property == :units)) do
      %{value: unit} when is_atom(unit) -> unit
      _properties -> nil
    end
  end

  defp chart_has_data?(%{series: series}) when is_list(series) do
    Enum.any?(series, fn %{points: points} -> points != [] end)
  end

  defp chart_has_data?(_series), do: false

  defp trend_chart_download(socket, format) do
    case socket.assigns.trend_chart_data do
      data when is_map(data) ->
        object = socket.assigns.object
        start_dt = parse_trend_chart_datetime(socket.assigns.trend_chart_start)
        end_dt = parse_trend_chart_datetime(socket.assigns.trend_chart_end)

        {content, mime, ext} =
          case format do
            :json ->
              {TrendLogExport.to_json(data, object: object, start_dt: start_dt, end_dt: end_dt),
               "application/json", "json"}

            _socket ->
              {TrendLogExport.to_csv(data), "text/csv", "csv"}
          end

        filename = TrendLogExport.filename(object.type, object.instance, start_dt, end_dt, ext)

        push_event(socket, "download_file", %{
          content: content,
          filename: filename,
          mime: mime
        })

      _socket ->
        socket
    end
  end

  defp trend_chart_event_payload(%{series: series} = data) when is_list(series) do
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
        empty_label: "Keine plottbaren Datensätze im gewählten Zeitraum."
      }
    end
  end

  defp trend_chart_event_payload(_series),
    do: %{series: [], scales: [], empty_label: "Keine Daten geladen."}

  defp file_object?(socket) do
    match?(%{type: :file}, socket.assigns.object)
  end
end
