defmodule BacViewWeb.AlarmTable do
  @moduledoc false

  alias BacView.BACnet.Protocol.EventFormatter
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacViewWeb.StatusFlagsIcons
  alias BacViewWeb.TableSort

  @event_columns ~w(object state type ack updated_at)
  @active_alarm_columns ~w(object_id type name description status alarm_since updated_at)
  @notification_columns ~w(received object type state priority message)

  @spec event_sort_columns() :: [String.t()]
  def event_sort_columns(), do: @event_columns

  @spec active_alarm_sort_columns() :: [String.t()]
  def active_alarm_sort_columns(), do: @active_alarm_columns

  @spec notification_sort_columns() :: [String.t()]
  def notification_sort_columns(), do: @notification_columns

  @spec normalize_event_sort_column(term()) :: String.t() | nil
  def normalize_event_sort_column(column) when column in @event_columns, do: column

  def normalize_event_sort_column(column) when is_atom(column),
    do: normalize_event_sort_column(Atom.to_string(column))

  def normalize_event_sort_column(_column), do: nil

  @spec normalize_active_alarm_sort_column(term()) :: String.t() | nil
  def normalize_active_alarm_sort_column(column) when column in @active_alarm_columns, do: column

  def normalize_active_alarm_sort_column(column) when is_atom(column),
    do: normalize_active_alarm_sort_column(Atom.to_string(column))

  def normalize_active_alarm_sort_column(_column), do: nil

  @spec normalize_notification_sort_column(term()) :: String.t() | nil
  def normalize_notification_sort_column(column) when column in @notification_columns, do: column

  def normalize_notification_sort_column(column) when is_atom(column),
    do: normalize_notification_sort_column(Atom.to_string(column))

  def normalize_notification_sort_column(_column), do: nil

  @spec normalize_sort_dir(term()) :: :asc | :desc
  def normalize_sort_dir(dir), do: TableSort.normalize_dir(dir)

  @spec toggle_sort(String.t() | nil, :asc | :desc, String.t()) :: {String.t(), :asc | :desc}
  def toggle_sort(sort_by, sort_dir, column),
    do: TableSort.toggle_sort(sort_by, sort_dir, column)

  @spec sorted_events([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_events(events, sort_by, sort_dir) do
    TableSort.sort(events, sort_by, sort_dir, @event_columns, &event_sort_key/2)
  end

  @spec sorted_active_alarms([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_active_alarms(objects, sort_by, sort_dir) do
    TableSort.sort(objects, sort_by, sort_dir, @active_alarm_columns, &active_alarm_sort_key/2)
  end

  @spec sorted_notifications([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_notifications(notifications, sort_by, sort_dir) do
    TableSort.sort(
      notifications,
      sort_by,
      sort_dir,
      @notification_columns,
      &notification_sort_key/2
    )
  end

  defp event_sort_key(event, "object"),
    do: object_id_key(Map.get(event, :object_id))

  defp event_sort_key(event, "state"),
    do: TableSort.nullable_string_key(atom_key(Map.get(event, :event_state)))

  defp event_sort_key(event, "type") do
    notify = TableSort.nullable_string_key(atom_key(Map.get(event, :notify_type)))
    event_type = TableSort.nullable_string_key(atom_key(Map.get(event, :event_type)))
    {notify, event_type}
  end

  defp event_sort_key(event, "ack"),
    do: TableSort.nullable_string_key(EventFormatter.ack_status_label(event))

  defp event_sort_key(event, "updated_at"),
    do: TableSort.datetime_key(Map.get(event, :updated_at))

  defp active_alarm_sort_key(obj, "object_id"), do: {obj.type, obj.instance}

  defp active_alarm_sort_key(obj, "type"),
    do: TableSort.nullable_string_key(ObjectTypes.short_label(obj.type))

  defp active_alarm_sort_key(obj, "name"),
    do: TableSort.nullable_string_key(Map.get(obj, :name))

  defp active_alarm_sort_key(obj, "description"),
    do: TableSort.nullable_string_key(Map.get(obj, :description))

  defp active_alarm_sort_key(obj, "status"),
    do: length(StatusFlagsIcons.active_flags(Map.get(obj, :status_flags)))

  defp active_alarm_sort_key(obj, "alarm_since"),
    do: Map.get(obj, :alarm_since_sort_key, 0)

  defp active_alarm_sort_key(obj, "updated_at"),
    do: TableSort.datetime_key(Map.get(obj, :updated_at))

  defp notification_sort_key(notif, "received"),
    do: TableSort.datetime_key(Map.get(notif, :received_at, Map.get(notif, :updated_at)))

  defp notification_sort_key(notif, "object"),
    do: object_id_key(Map.get(notif, :object_id))

  defp notification_sort_key(notif, "type") do
    notify = TableSort.nullable_string_key(atom_key(Map.get(notif, :notify_type)))
    event_type = TableSort.nullable_string_key(atom_key(Map.get(notif, :event_type)))
    {notify, event_type}
  end

  defp notification_sort_key(notif, "state") do
    state = Map.get(notif, :to_state) || Map.get(notif, :event_state)
    TableSort.nullable_string_key(atom_key(state))
  end

  defp notification_sort_key(notif, "priority"),
    do: Map.get(notif, :priority) || -1

  defp notification_sort_key(notif, "message"),
    do: TableSort.nullable_string_key(Map.get(notif, :message_text))

  defp object_id_key(%{type: type, instance: instance}), do: {type, instance}
  defp object_id_key(_object_id_key), do: {nil, -1}

  defp atom_key(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_key(_value), do: nil
end
