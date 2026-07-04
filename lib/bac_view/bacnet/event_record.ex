defmodule BacView.BACnet.EventRecord do
  @moduledoc """
  Normalized BACnet event records for display and summary statistics.
  """
  alias BACnet.Protocol.AlarmSummary
  alias BACnet.Protocol.EventInformation
  alias BACnet.Protocol.EventTransitionBits
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.ConfirmedEventNotification
  alias BACnet.Protocol.Services.UnconfirmedEventNotification

  @active_states [:fault, :offnormal, :high_limit, :low_limit, :life_safety_alarm]

  @type t :: %{
          device_id: non_neg_integer(),
          object_id: ObjectIdentifier.t(),
          event_state: atom(),
          priority: non_neg_integer() | nil,
          notify_type: atom() | nil,
          notification_class: non_neg_integer() | nil,
          message_text: String.t() | nil,
          event_type: atom() | nil,
          from_state: atom() | nil,
          to_state: atom() | nil,
          acknowledged_transitions: EventTransitionBits.t() | nil,
          event_timestamps: term() | nil,
          event_priorities: {non_neg_integer(), non_neg_integer(), non_neg_integer()} | nil,
          ack_required: boolean() | nil,
          source: :poll | :notification,
          updated_at: DateTime.t()
        }

  @spec key(non_neg_integer(), ObjectIdentifier.t()) ::
          {non_neg_integer(), atom(), non_neg_integer()}
  def key(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    {device_id, type, instance}
  end

  @spec from_alarm_summary(non_neg_integer(), AlarmSummary.t()) :: t()
  def from_alarm_summary(device_id, %AlarmSummary{} = summary) do
    %{
      device_id: device_id,
      object_id: summary.object_identifier,
      event_state: summary.alarm_state,
      priority: nil,
      notify_type: :alarm,
      notification_class: nil,
      message_text: nil,
      event_type: nil,
      from_state: nil,
      to_state: nil,
      acknowledged_transitions: summary.acknowledged_transitions,
      event_timestamps: nil,
      event_priorities: nil,
      ack_required: nil,
      source: :poll,
      updated_at: DateTime.utc_now()
    }
  end

  @spec from_event_information(non_neg_integer(), EventInformation.t()) :: t()
  def from_event_information(device_id, %EventInformation{} = info) do
    %{
      device_id: device_id,
      object_id: info.object_identifier,
      event_state: info.event_state,
      priority: priority_for_state(info.event_state, info.event_priorities),
      notify_type: info.notify_type,
      notification_class: nil,
      message_text: nil,
      event_type: nil,
      from_state: nil,
      to_state: nil,
      acknowledged_transitions: info.acknowledged_transitions,
      event_timestamps: info.event_timestamps,
      event_priorities: info.event_priorities,
      ack_required: nil,
      source: :poll,
      updated_at: DateTime.utc_now()
    }
  end

  @spec from_notification(
          non_neg_integer(),
          ConfirmedEventNotification.t() | UnconfirmedEventNotification.t()
        ) ::
          t()
  def from_notification(device_id, notification) do
    %{
      device_id: device_id,
      object_id: notification.event_object,
      event_state: notification.to_state || :normal,
      priority: notification.priority,
      notify_type: notification.notify_type,
      notification_class: Map.get(notification, :notification_class),
      message_text: notification.message_text,
      event_type: notification.event_type,
      from_state: notification.from_state,
      to_state: notification.to_state,
      acknowledged_transitions: nil,
      event_timestamps: nil,
      event_priorities: nil,
      ack_required: Map.get(notification, :ack_required),
      source: :notification,
      updated_at: DateTime.utc_now()
    }
  end

  @spec merge(t(), t()) :: t()
  def merge(existing, incoming) do
    existing
    |> Map.merge(incoming, fn _key, _existing, incoming_val -> incoming_val end)
    |> Map.update!(:updated_at, fn _existing -> DateTime.utc_now() end)
  end

  @spec active?(t() | map()) :: boolean()
  def active?(%{event_state: state}), do: state in @active_states

  @spec unacknowledged?(t() | map()) :: boolean()
  def unacknowledged?(%{ack_required: true}), do: true

  def unacknowledged?(%{
        event_state: state,
        acknowledged_transitions: %EventTransitionBits{} = ack
      }) do
    active?(%{event_state: state}) and not transition_acknowledged?(state, ack)
  end

  def unacknowledged?(_unacknowledged), do: false

  @spec summary([t() | map()]) :: %{
          active_count: non_neg_integer(),
          unacknowledged_count: non_neg_integer(),
          highest_priority: non_neg_integer() | nil
        }
  def summary(events) when is_list(events) do
    active = Enum.filter(events, &active?/1)
    unack = Enum.filter(events, &unacknowledged?/1)

    priorities =
      active
      |> Enum.map(&effective_priority/1)
      |> Enum.reject(&is_nil/1)

    %{
      active_count: length(active),
      unacknowledged_count: length(unack),
      highest_priority: if(priorities == [], do: nil, else: Enum.min(priorities))
    }
  end

  @spec effective_priority(t() | map()) :: non_neg_integer() | nil
  def effective_priority(%{priority: priority}) when is_integer(priority), do: priority

  def effective_priority(%{event_state: state, event_priorities: priorities})
      when not is_nil(priorities) do
    priority_for_state(state, priorities)
  end

  def effective_priority(_priority), do: nil

  defp priority_for_state(state, {off, fault, normal}) do
    case state do
      :offnormal -> off
      :high_limit -> off
      :low_limit -> off
      :life_safety_alarm -> off
      :fault -> fault
      :normal -> normal
      _state -> nil
    end
  end

  defp transition_acknowledged?(:offnormal, %EventTransitionBits{to_offnormal: ack}), do: ack
  defp transition_acknowledged?(:high_limit, %EventTransitionBits{to_offnormal: ack}), do: ack
  defp transition_acknowledged?(:low_limit, %EventTransitionBits{to_offnormal: ack}), do: ack

  defp transition_acknowledged?(:life_safety_alarm, %EventTransitionBits{to_offnormal: ack}),
    do: ack

  defp transition_acknowledged?(:fault, %EventTransitionBits{to_fault: ack}), do: ack
  defp transition_acknowledged?(_state, _ack), do: true
end
