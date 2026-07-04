defmodule BacView.BACnet.Protocol.BacnetCalendarFormat do
  @moduledoc false

  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp

  @dash "—"

  @spec format(term()) :: String.t()
  def format(%BACnetDateTime{} = datetime), do: format_datetime(datetime)
  def format(%BACnetDate{} = date), do: format_date(date)
  def format(%BACnetTime{} = time), do: format_time(time)
  def format(%BACnetTimestamp{} = timestamp), do: format_timestamp(timestamp)
  def format(_format), do: @dash

  @spec format_datetime(BACnetDateTime.t()) :: String.t()
  def format_datetime(%BACnetDateTime{} = datetime) do
    with {:ok, date} <- format_date_value(datetime.date),
         {:ok, time} <- format_time_value(datetime.time) do
      "#{date} #{time}"
    else
      _datetime -> @dash
    end
  end

  @spec format_date(BACnetDate.t()) :: String.t()
  def format_date(%BACnetDate{} = date) do
    case format_date_value(date) do
      {:ok, formatted} -> formatted
      _datetime -> @dash
    end
  end

  @spec format_time(BACnetTime.t()) :: String.t()
  def format_time(%BACnetTime{} = time) do
    case format_time_value(time) do
      {:ok, formatted} -> formatted
      _time -> @dash
    end
  end

  @spec format_timestamp(BACnetTimestamp.t()) :: String.t()
  def format_timestamp(%BACnetTimestamp{type: :datetime, datetime: %BACnetDateTime{} = datetime}) do
    format_datetime(datetime)
  end

  def format_timestamp(%BACnetTimestamp{type: :time, time: %BACnetTime{} = time}) do
    format_time(time)
  end

  def format_timestamp(%BACnetTimestamp{type: :sequence_number, sequence_number: number})
      when is_integer(number) do
    "##{number}"
  end

  def format_timestamp(_format_timestamp), do: @dash

  defp format_date_value(%BACnetDate{} = date) do
    if BACnetDate.specific?(date) do
      case BACnetDate.to_date(date) do
        {:ok, %Date{} = value} -> {:ok, Calendar.strftime(value, "%d.%m.%Y")}
      end
    else
      :error
    end
  end

  defp format_time_value(%BACnetTime{} = time) do
    if BACnetTime.specific?(time) do
      case BACnetTime.to_time(time) do
        {:ok, %Time{} = value} ->
          {:ok, format_time_parts(value, time.hundredth)}

        _time ->
          :error
      end
    else
      :error
    end
  end

  defp format_time_parts(%Time{} = time, hundredth) do
    base = Calendar.strftime(time, "%H:%M:%S")

    if is_integer(hundredth) and hundredth >= 0 and hundredth <= 99 do
      milliseconds = hundredth * 10

      "#{base}.#{String.pad_leading(Integer.to_string(milliseconds), 3, "0")}"
    else
      base
    end
  end
end
