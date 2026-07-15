defmodule BacView.BACnet.Protocol.EventTimestamp do
  @moduledoc false

  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.EventTimestamps
  alias BacView.Timezone

  @spec alarm_since(EventTimestamps.t() | nil, atom()) :: %{
          at: DateTime.t() | nil,
          label: String.t(),
          sort_key: integer()
        }
  def alarm_since(timestamps, event_state) when is_struct(timestamps, EventTimestamps) do
    timestamps
    |> timestamp_for_state(event_state)
    |> format_timestamp()
  end

  def alarm_since(_timestamps, _event_state) do
    %{at: nil, label: "-", sort_key: 0}
  end

  defp timestamp_for_state(%EventTimestamps{} = timestamps, state) do
    case state do
      :offnormal -> timestamps.to_offnormal
      :high_limit -> timestamps.to_offnormal
      :low_limit -> timestamps.to_offnormal
      :life_safety_alarm -> timestamps.to_offnormal
      :fault -> timestamps.to_fault
      :normal -> timestamps.to_normal
      _state -> nil
    end
  end

  defp format_timestamp(%BACnetTimestamp{type: :datetime, datetime: datetime})
       when not is_nil(datetime) do
    case BACnetDateTime.to_datetime(datetime) do
      {:ok, %DateTime{} = at} ->
        %{
          at: at,
          label: Timezone.format(at, "%d.%m.%Y %H:%M:%S"),
          sort_key: DateTime.to_unix(at, :microsecond)
        }

      _format_timestamp ->
        unknown_timestamp()
    end
  end

  defp format_timestamp(%BACnetTimestamp{type: :time, time: %BACnetTime{} = time}) do
    %{at: nil, label: format_bacnet_time(time), sort_key: 0}
  end

  defp format_timestamp(%BACnetTimestamp{type: :sequence_number, sequence_number: number})
       when is_integer(number) do
    %{at: nil, label: "##{number}", sort_key: number}
  end

  defp format_timestamp(_format_timestamp), do: unknown_timestamp()

  defp unknown_timestamp(), do: %{at: nil, label: "-", sort_key: 0}

  defp format_bacnet_time(%BACnetTime{hour: hour, minute: minute, second: second}) do
    hour = String.pad_leading(Integer.to_string(hour), 2, "0")
    minute = String.pad_leading(Integer.to_string(minute), 2, "0")
    second = String.pad_leading(Integer.to_string(second), 2, "0")
    "#{hour}:#{minute}:#{second}"
  end
end
