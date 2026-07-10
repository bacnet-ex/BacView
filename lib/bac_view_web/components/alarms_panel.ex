defmodule BacViewWeb.AlarmsPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.EventRecord
  alias BacView.BACnet.Protocol.EventFormatter
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacViewWeb.AlarmTable
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.SortHeader
  alias BacViewWeb.StatusFlagsIcons

  attr(:alarm_view, :string, required: true)
  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:alarm_view_paths, :map, required: true)
  attr(:events, :list, required: true)
  attr(:notifications, :list, required: true)
  attr(:objects, :list, required: true)
  attr(:active_alarm_objects, :list, required: true)
  attr(:summary, :map, required: true)
  attr(:refreshing, :boolean, default: false)
  attr(:nc_subscribing, :boolean, default: false)
  attr(:nc_progress, :map, default: %{done: 0, total: 0})
  attr(:nc_enrolled_count, :integer, default: 0)
  attr(:nc_total, :integer, default: 0)
  attr(:alarm_events_sort_by, :string, default: nil)
  attr(:alarm_events_sort_dir, :atom, default: :asc)
  attr(:active_alarms_sort_by, :string, default: nil)
  attr(:active_alarms_sort_dir, :atom, default: :asc)
  attr(:alarm_notifications_sort_by, :string, default: nil)
  attr(:alarm_notifications_sort_dir, :atom, default: :asc)

  def alarms_panel(assigns) do
    assigns = assign(assigns, :object_descriptions, object_descriptions_map(assigns.objects))

    ~H"""
    <div class="space-y-5">
      <div class="bac-tabs">
        <.link
          patch={@alarm_view_paths["event_information"]}
          class={["bac-tab", @alarm_view == "event_information" && "bac-tab-active"]}
          id="alarm-subtab-event-information"
        >
          <.icon name="hero-information-circle" class="size-4" />
          {t(@locale, @locale_version, "Ereignisinformation")}
        </.link>
        <.link
          patch={@alarm_view_paths["active_alarms"]}
          class={["bac-tab", @alarm_view == "active_alarms" && "bac-tab-active"]}
          id="alarm-subtab-active-alarms"
        >
          <.icon name="hero-bell-alert" class="size-4" />
          {t(@locale, @locale_version, "Aktive Alarme")}
          <span
            :if={length(@active_alarm_objects) > 0}
            class="bac-badge bac-badge-sm bac-badge-error"
          >
            {length(@active_alarm_objects)}
          </span>
        </.link>
        <.link
          patch={@alarm_view_paths["notifications"]}
          class={["bac-tab", @alarm_view == "notifications" && "bac-tab-active"]}
          id="alarm-subtab-notifications"
        >
          <.icon name="hero-inbox-arrow-down" class="size-4" />
          {t(@locale, @locale_version, "Meldungen")}
          <span
            :if={length(@notifications) > 0}
            class="bac-badge bac-badge-sm bac-badge-ghost"
          >
            {length(@notifications)}
          </span>
        </.link>
      </div>

      <.event_information_panel
        :if={@alarm_view == "event_information"}
        device_id={@device_id}
        list_opts={@list_opts}
        events={@events}
        object_descriptions={@object_descriptions}
        summary={@summary}
        refreshing={@refreshing}
        sort_by={@alarm_events_sort_by}
        sort_dir={@alarm_events_sort_dir}
        locale={@locale}
        locale_version={@locale_version}
      />

      <.active_alarms_panel
        :if={@alarm_view == "active_alarms"}
        device_id={@device_id}
        list_opts={@list_opts}
        objects={@active_alarm_objects}
        nc_subscribing={@nc_subscribing}
        nc_progress={@nc_progress}
        nc_enrolled_count={@nc_enrolled_count}
        nc_total={@nc_total}
        sort_by={@active_alarms_sort_by}
        sort_dir={@active_alarms_sort_dir}
        locale={@locale}
        locale_version={@locale_version}
      />

      <.notifications_panel
        :if={@alarm_view == "notifications"}
        device_id={@device_id}
        list_opts={@list_opts}
        notifications={@notifications}
        object_descriptions={@object_descriptions}
        sort_by={@alarm_notifications_sort_by}
        sort_dir={@alarm_notifications_sort_dir}
        locale={@locale}
        locale_version={@locale_version}
      />
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:events, :list, required: true)
  attr(:object_descriptions, :map, required: true)
  attr(:summary, :map, required: true)
  attr(:refreshing, :boolean, default: false)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp event_information_panel(assigns) do
    assigns =
      assign(
        assigns,
        :sorted_events,
        AlarmTable.sorted_events(assigns.events, assigns.sort_by, assigns.sort_dir)
      )

    ~H"""
    <div class="space-y-5" id="alarm-panel-event-information">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div class="bac-stat">
          <div class="bac-stat-label">{t(@locale, @locale_version, "Aktive Alarme")}</div>
          <div class={[
            "bac-stat-value",
            @summary.active_count > 0 && "bac-stat-value-error"
          ]}>
            {@summary.active_count}
          </div>
        </div>

        <div class="bac-stat">
          <div class="bac-stat-label">{t(@locale, @locale_version, "Unquittiert")}</div>
          <div class={[
            "bac-stat-value",
            @summary.unacknowledged_count > 0 && "bac-stat-value-warning"
          ]}>
            {@summary.unacknowledged_count}
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          phx-click="refresh_alarms"
          disabled={@refreshing}
          class="bac-btn bac-btn-primary bac-btn-sm"
          id="refresh-alarms-btn"
        >
          <.icon :if={@refreshing} name="hero-arrow-path" class="size-4 animate-spin" />
          {t(@locale, @locale_version, "Ereignisse abrufen")}
        </button>
        <button
          type="button"
          phx-click="export_events"
          phx-value-format="json"
          disabled={@events == []}
          class="bac-btn bac-btn-ghost bac-btn-sm"
          id="export-events-json-btn"
        >
          {t(@locale, @locale_version, "JSON")}
        </button>
        <button
          type="button"
          phx-click="export_events"
          phx-value-format="csv"
          disabled={@events == []}
          class="bac-btn bac-btn-ghost bac-btn-sm"
          id="export-events-csv-btn"
        >
          {t(@locale, @locale_version, "CSV")}
        </button>
      </div>

      <p :if={@events == []} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Keine Ereignisse. Klicken Sie auf „Ereignisse abrufen“, um GetAlarmSummary abzufragen.")}
      </p>

      <div :if={@events != []} class="bac-table-wrap">
        <table class="bac-table" id="alarms-table">
          <thead>
            <tr>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_events"
                  id_prefix="alarm-event-sort"
                  column="object"
                  label={t(@locale, @locale_version, "Objekt")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_events"
                  id_prefix="alarm-event-sort"
                  column="state"
                  label={t(@locale, @locale_version, "Zustand")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_events"
                  id_prefix="alarm-event-sort"
                  column="type"
                  label={t(@locale, @locale_version, "Typ")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_events"
                  id_prefix="alarm-event-sort"
                  column="ack"
                  label={t(@locale, @locale_version, "Quittierung")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_events"
                  id_prefix="alarm-event-sort"
                  column="updated_at"
                  label={t(@locale, @locale_version, "Aktualisiert")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={event <- @sorted_events}
              id={"alarm-#{event.object_id.type}-#{event.object_id.instance}"}
              class={[
                EventRecord.active?(event) && "bac-row-alarm"
              ]}
            >
              <td>
                <.object_cell
                  device_id={@device_id}
                  list_opts={@list_opts}
                  object_id={event.object_id}
                  description={Map.get(@object_descriptions, {event.object_id.type, event.object_id.instance})}
                />
              </td>
              <td>
                <span class={[
                  "bac-badge bac-badge-sm",
                  state_badge_class(event.event_state)
                ]}>
                  {EventFormatter.event_state_label(event.event_state)}
                </span>
              </td>
              <td>
                {EventFormatter.notify_type_label(event.notify_type)}
                <span :if={event.event_type} class="bac-text-faint block text-xs">
                  {EventFormatter.event_type_label(event.event_type)}
                </span>
              </td>
              <td>{EventFormatter.ack_status_label(event)}</td>
              <td class="bac-text-faint">{format_time(event.updated_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:objects, :list, required: true)
  attr(:nc_subscribing, :boolean, default: false)
  attr(:nc_progress, :map, default: %{done: 0, total: 0})
  attr(:nc_enrolled_count, :integer, default: 0)
  attr(:nc_total, :integer, default: 0)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp active_alarms_panel(assigns) do
    assigns =
      assign(
        assigns,
        :sorted_objects,
        AlarmTable.sorted_active_alarms(assigns.objects, assigns.sort_by, assigns.sort_dir)
      )

    ~H"""
    <div class="space-y-5" id="alarm-panel-active-alarms">
      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          phx-click="subscribe_notification_classes"
          disabled={@nc_subscribing || (@nc_enrolled_count > 0 && @nc_enrolled_count >= @nc_total && @nc_total > 0)}
          class="bac-btn bac-btn-primary bac-btn-sm"
          id="subscribe-notification-classes-btn"
        >
          <.icon :if={@nc_subscribing} name="hero-arrow-path" class="size-4 animate-spin" />
          {t(@locale, @locale_version, "Empfängerliste eintragen")}
        </button>
        <button
          type="button"
          phx-click="unsubscribe_notification_classes"
          disabled={@nc_subscribing || @nc_enrolled_count == 0}
          class="bac-btn bac-btn-ghost bac-btn-sm"
          id="unsubscribe-notification-classes-btn"
        >
          {t(@locale, @locale_version, "Empfängerliste entfernen")}
        </button>
        <span :if={@nc_enrolled_count > 0} class="bac-badge bac-badge-sm bac-badge-success">
          {t(@locale, @locale_version, "%{count} Meldungsklassen", count: @nc_enrolled_count)}
        </span>
      </div>

      <p class="text-sm bac-text-muted">
        {t(@locale, @locale_version, "Trägt BacView per AddListElement in die recipient_list aller Meldungsklassen ein (Fallback: WriteProperty).")}
      </p>

      <div :if={@nc_subscribing} class="max-w-md">
        <progress
          class="bac-progress"
          value={@nc_progress.done}
          max={max(@nc_progress.total, 1)}
        >
        </progress>
        <p class="text-xs bac-text-faint mt-1.5">
          {t(@locale, @locale_version, "%{done} / %{total}", done: @nc_progress.done, total: @nc_progress.total)}
        </p>
      </div>

      <p :if={@objects == []} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Keine aktiven Alarme. Objekte mit In-Alarm- oder Störungs-Status erscheinen hier.")}
      </p>

      <div :if={@objects != []} class="bac-table-wrap">
        <table class="bac-table" id="active-alarms-table">
          <thead>
            <tr>
              <th>
                <SortHeader.sort_header
                  event="sort_active_alarms"
                  id_prefix="active-alarm-sort"
                  column="object_id"
                  label={t(@locale, @locale_version, "Objekt")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_active_alarms"
                  id_prefix="active-alarm-sort"
                  column="type"
                  label={t(@locale, @locale_version, "Typ")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_active_alarms"
                  id_prefix="active-alarm-sort"
                  column="name"
                  label={t(@locale, @locale_version, "Name")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_active_alarms"
                  id_prefix="active-alarm-sort"
                  column="description"
                  label={t(@locale, @locale_version, "Beschreibung")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_active_alarms"
                  id_prefix="active-alarm-sort"
                  column="status"
                  label={t(@locale, @locale_version, "Status")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_active_alarms"
                  id_prefix="active-alarm-sort"
                  column="updated_at"
                  label={t(@locale, @locale_version, "Aktualisiert")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={obj <- @sorted_objects}
              id={"active-alarm-#{obj.type}-#{obj.instance}"}
              class="bac-row-alarm"
            >
              <td
                class="bac-mono bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, obj.type, obj.instance, @list_opts))}
              >
                {obj.type}:{obj.instance}
              </td>
              <td>{ObjectTypes.short_label(obj.type)}</td>
              <td class="max-w-xs truncate">{obj.name || "—"}</td>
              <td class="max-w-sm truncate" title={Map.get(obj, :description)}>
                {Map.get(obj, :description) || "—"}
              </td>
              <td>
                <StatusFlagsIcons.status_flags_icons
                  flags={Map.get(obj, :status_flags)}
                  locale={@locale}
                  locale_version={@locale_version}
                />
              </td>
              <td class="bac-text-faint">{format_time(Map.get(obj, :updated_at))}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:notifications, :list, required: true)
  attr(:object_descriptions, :map, required: true)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp notifications_panel(assigns) do
    assigns =
      assign(
        assigns,
        :sorted_notifications,
        AlarmTable.sorted_notifications(
          assigns.notifications,
          assigns.sort_by,
          assigns.sort_dir
        )
      )

    ~H"""
    <div class="space-y-5" id="alarm-panel-notifications">
      <p :if={@notifications == []} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Noch keine Ereignismeldungen empfangen.")}
      </p>

      <div :if={@notifications != []} class="bac-table-wrap">
        <table class="bac-table" id="notifications-table">
          <thead>
            <tr>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_notifications"
                  id_prefix="alarm-notification-sort"
                  column="received"
                  label={t(@locale, @locale_version, "Empfangen")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_notifications"
                  id_prefix="alarm-notification-sort"
                  column="object"
                  label={t(@locale, @locale_version, "Objekt")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_notifications"
                  id_prefix="alarm-notification-sort"
                  column="type"
                  label={t(@locale, @locale_version, "Typ")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_notifications"
                  id_prefix="alarm-notification-sort"
                  column="state"
                  label={t(@locale, @locale_version, "Zustand")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_notifications"
                  id_prefix="alarm-notification-sort"
                  column="priority"
                  label={t(@locale, @locale_version, "Priorität")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_alarm_notifications"
                  id_prefix="alarm-notification-sort"
                  column="message"
                  label={t(@locale, @locale_version, "Meldung")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={notif <- @sorted_notifications}
              id={"notification-#{notif.log_id}"}
              class={[
                EventRecord.active?(notif) && "bac-row-alarm"
              ]}
            >
              <td class="bac-text-faint whitespace-nowrap">
                {format_time(Map.get(notif, :received_at, notif.updated_at))}
              </td>
              <td>
                <.object_cell
                  device_id={@device_id}
                  list_opts={@list_opts}
                  object_id={notif.object_id}
                  description={Map.get(@object_descriptions, {notif.object_id.type, notif.object_id.instance})}
                />
              </td>
              <td>
                {EventFormatter.notify_type_label(notif.notify_type)}
                <span :if={notif.event_type} class="bac-text-faint block text-xs">
                  {EventFormatter.event_type_label(notif.event_type)}
                </span>
              </td>
              <td>
                <span class="bac-text-faint text-xs">
                  {state_transition_label(notif)}
                </span>
                <span class={[
                  "bac-badge bac-badge-sm mt-0.5",
                  state_badge_class(notif.to_state || notif.event_state)
                ]}>
                  {EventFormatter.event_state_label(notif.to_state || notif.event_state)}
                </span>
              </td>
              <td class="bac-mono">{EventFormatter.priority_label(notif.priority)}</td>
              <td class="max-w-sm truncate">{notif.message_text || "—"}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @description_preview_length 150

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:object_id, :map, required: true)
  attr(:description, :string, default: nil)

  defp object_cell(assigns) do
    {preview, truncated?} = preview_text(assigns.description, @description_preview_length)

    assigns =
      assigns
      |> assign(:description_preview, preview)
      |> assign(:description_truncated?, truncated?)
      |> assign(
        :object_href,
        object_path(
          assigns.device_id,
          assigns.object_id.type,
          assigns.object_id.instance,
          assigns.list_opts
        )
      )

    ~H"""
    <.link navigate={@object_href} class="bac-mono hover:underline">
      {@object_id.type}:{@object_id.instance}
    </.link>
    <span
      :if={@description_preview}
      class="block text-xs bac-text-faint whitespace-normal break-words"
      title={if(@description_truncated?, do: @description, else: nil)}
    >
      {@description_preview}
    </span>
    """
  end

  defp preview_text(nil, _max), do: {nil, false}

  defp preview_text(text, max) when is_binary(text) do
    if String.length(text) > max do
      {String.slice(text, 0, max) <> "…", true}
    else
      {text, false}
    end
  end

  defp object_descriptions_map(objects) when is_list(objects) do
    Map.new(objects, fn obj ->
      {{obj.type, obj.instance}, object_description(obj)}
    end)
  end

  defp object_description(%{description: description}) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_description(_objects), do: nil

  defp state_transition_label(notif) do
    from = notif.from_state
    to = notif.to_state || notif.event_state

    if from && to do
      "#{EventFormatter.event_state_label(from)} → #{EventFormatter.event_state_label(to)}"
    else
      ""
    end
  end

  defp state_badge_class(:normal), do: "bac-badge-success"
  defp state_badge_class(:fault), do: "bac-badge-error"
  defp state_badge_class(:offnormal), do: "bac-badge-warning"
  defp state_badge_class(:high_limit), do: "bac-badge-warning"
  defp state_badge_class(:low_limit), do: "bac-badge-warning"
  defp state_badge_class(:life_safety_alarm), do: "bac-badge-error"
  defp state_badge_class(_normal), do: "bac-badge-ghost"

  defp format_time(%DateTime{} = dt), do: BacView.Timezone.format(dt, "%H:%M:%S")
  defp format_time(_format_time), do: "—"

  defp object_path(device_id, type, instance, list_opts) do
    url_opts =
      list_opts
      |> Keyword.delete(:device_id)
      |> Keyword.put(:tab, "alarms")

    DeviceUrl.object_path(device_id, type, instance, url_opts)
  end
end
