defmodule BacView.BACnet.Protocol.EventFormatter do
  @moduledoc """
  Localized labels for BACnet event-related enumerations.
  """

  use Gettext, backend: BacViewWeb.Gettext

  alias BacView.BACnet.EventRecord

  @spec event_state_label(atom() | nil) :: String.t()
  def event_state_label(nil), do: "-"

  def event_state_label(state) do
    case state do
      :normal -> gettext("Normal")
      :fault -> gettext("Störung")
      :offnormal -> gettext("Abnormal")
      :high_limit -> gettext("Obergrenze")
      :low_limit -> gettext("Untergrenze")
      :life_safety_alarm -> gettext("Lebensschutz-Alarm")
      other -> Atom.to_string(other)
    end
  end

  @spec notification_class_label(non_neg_integer() | nil) :: String.t()
  def notification_class_label(nil), do: "-"
  def notification_class_label(notification_class), do: "NC #{notification_class}"

  @spec notify_type_label(atom() | nil) :: String.t()
  def notify_type_label(nil), do: "-"

  def notify_type_label(type) do
    case type do
      :alarm -> gettext("Alarm")
      :event -> gettext("Ereignis")
      :ack_notification -> gettext("Quittierung")
      other -> Atom.to_string(other)
    end
  end

  @spec event_type_label(atom() | nil) :: String.t()
  def event_type_label(nil), do: "-"

  def event_type_label(type) do
    case type do
      :change_of_bitstring -> gettext("Bitstring-Änderung")
      :change_of_state -> gettext("Zustandsänderung")
      :change_of_value -> gettext("Wertänderung")
      :command_failure -> gettext("Befehlsfehler")
      :floating_limit -> gettext("Grenzwert")
      :out_of_range -> gettext("Ausserhalb Bereich")
      :complex_event_type -> gettext("Komplex")
      :buffer_ready -> gettext("Puffer bereit")
      :change_of_life_safety -> gettext("Lebensschutz-Änderung")
      :extended -> gettext("Erweitert")
      :change_of_discrete_value -> gettext("Diskrete Wertänderung")
      :change_of_timer -> gettext("Timer-Änderung")
      other -> Atom.to_string(other)
    end
  end

  @spec priority_label(non_neg_integer() | nil) :: String.t()
  def priority_label(nil), do: "-"
  def priority_label(priority), do: Integer.to_string(priority)

  @spec ack_status_label(map()) :: String.t()
  def ack_status_label(%{ack_required: true}), do: gettext("Quittierung erforderlich")

  def ack_status_label(event) do
    if EventRecord.unacknowledged?(event) do
      gettext("Unquittiert")
    else
      gettext("Quittiert")
    end
  end
end
