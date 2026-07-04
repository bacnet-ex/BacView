defmodule BacView.BACnet.EventExportTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    AlarmSummary,
    EventMessageTexts,
    EventTransitionBits,
    ObjectIdentifier
  }

  alias BacView.BACnet.{EventExport, EventRecord}

  test "enrich_event fills fields from object" do
    object_id = %ObjectIdentifier{type: :analog_input, instance: 3}
    updated_at = ~U[2026-06-27 14:30:00Z]

    event =
      EventRecord.from_alarm_summary(12, %AlarmSummary{
        object_identifier: object_id,
        alarm_state: :offnormal,
        acknowledged_transitions: %EventTransitionBits{
          to_offnormal: false,
          to_fault: true,
          to_normal: true
        }
      })
      |> Map.put(:updated_at, updated_at)

    object_details = %{
      description: "Raumtemperatur OG",
      object_name: "AI-Temp-OG",
      notify_type: :alarm,
      notification_class: 2,
      event_message_texts: %EventMessageTexts{
        to_offnormal: "Temperatur zu hoch",
        to_fault: "Sensor defekt",
        to_normal: "Temperatur normal"
      }
    }

    enriched = EventExport.enrich_event(event, object_details)

    assert enriched.description == "Raumtemperatur OG"
    assert enriched.object_name == "AI-Temp-OG"
    assert enriched.notification_class == 2
    assert enriched.message_text == "Temperatur zu hoch"
  end

  test "csv export uses semicolon separator and includes description" do
    object_id = %ObjectIdentifier{type: :analog_input, instance: 3}
    updated_at = ~U[2026-06-27 14:30:00Z]

    event =
      EventRecord.from_alarm_summary(12, %AlarmSummary{
        object_identifier: object_id,
        alarm_state: :offnormal,
        acknowledged_transitions: %EventTransitionBits{
          to_offnormal: false,
          to_fault: true,
          to_normal: true
        }
      })
      |> Map.put(:updated_at, updated_at)
      |> Map.put(:description, "Raumtemperatur")
      |> Map.put(:object_name, "AI-3")
      |> Map.put(:message_text, "Zu warm")

    csv = EventExport.format_export([event], :csv)

    assert String.starts_with?(
             csv,
             "object;description;name;event_state;notify_type;notification_class;message;source;updated_at\n"
           )

    [row] = String.split(csv, "\n", trim: true) |> Enum.drop(1)
    fields = String.split(row, ";")

    assert fields == [
             "\"analog_input:3\"",
             "\"Raumtemperatur\"",
             "\"AI-3\"",
             "offnormal",
             "alarm",
             "",
             "\"Zu warm\"",
             "poll",
             "\"2026-06-27T14:30:00Z\""
           ]
  end
end
