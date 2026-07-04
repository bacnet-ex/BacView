defmodule BacView.BACnet.Protocol.TrendLogReader do
  @moduledoc false

  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetError
  alias BACnet.Protocol.LogMultipleRecord
  alias BACnet.Protocol.LogRecord
  alias BACnet.Protocol.LogStatus
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectsUtility

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.Services.Ack.ReadRangeAck
  alias BacView.BACnet.DeviceSession

  @trend_log_types [:trend_log, :trend_log_multiple]
  @page_size 200
  @max_records 5_000

  @spec trend_log_type?(atom()) :: boolean()
  def trend_log_type?(type) when is_atom(type), do: type in @trend_log_types
  def trend_log_type?(_type), do: false

  @spec fetch_all(integer(), ObjectIdentifier.t()) :: {:ok, [map()]} | {:error, term()}
  def fetch_all(device_id, %ObjectIdentifier{} = object_id) do
    if trend_log_type?(object_id.type) do
      # nil range asks the device for all available items (ASHRAE 135 ReadRange).
      fetch_all_pages(device_id, object_id, nil, [])
    else
      {:error, :unsupported_object_type}
    end
  end

  @spec fetch_range(integer(), ObjectIdentifier.t(), NaiveDateTime.t(), NaiveDateTime.t()) ::
          {:ok, [map()]} | {:error, term()}
  def fetch_range(device_id, %ObjectIdentifier{} = object_id, start_dt, end_dt) do
    if trend_log_type?(object_id.type) do
      reference = BACnetDateTime.from_naive_datetime(start_dt)
      range = {:by_time, {reference, @page_size}}

      fetch_pages(device_id, object_id, range, start_dt, end_dt, [])
    else
      {:error, :unsupported_object_type}
    end
  end

  defp fetch_all_pages(_device_id, _object_id, _range, acc) when length(acc) >= @max_records do
    {:ok, Enum.take(acc, @max_records)}
  end

  defp fetch_all_pages(device_id, object_id, range, acc) do
    with {:ok, %ReadRangeAck{} = ack} <-
           DeviceSession.read_range(device_id, object_id, :log_buffer, range),
         {:ok, records} <- decode_records(object_id, ack.item_data),
         merged <- acc ++ records do
      cond do
        length(merged) >= @max_records ->
          {:ok, Enum.take(merged, @max_records)}

        done_paging_all?(ack, records) ->
          {:ok, merged}

        true ->
          case next_range(ack, range) do
            next when is_tuple(next) ->
              fetch_all_pages(device_id, object_id, next, merged)

            _device_id ->
              {:ok, merged}
          end
      end
    end
  end

  defp done_paging_all?(%ReadRangeAck{result_flags: flags, item_count: count}, records) do
    flags.last_item or not flags.more_items or count == 0 or records == []
  end

  defp fetch_pages(_device_id, _object_id, _range, _start_dt, _end_dt, acc)
       when length(acc) >= @max_records do
    {:ok, Enum.take(acc, @max_records)}
  end

  defp fetch_pages(device_id, object_id, range, start_dt, end_dt, acc) do
    with {:ok, %ReadRangeAck{} = ack} <-
           DeviceSession.read_range(device_id, object_id, :log_buffer, range),
         {:ok, records} <- decode_records(object_id, ack.item_data),
         filtered <- filter_records(records, start_dt, end_dt),
         merged <- acc ++ filtered do
      cond do
        length(merged) >= @max_records ->
          {:ok, Enum.take(merged, @max_records)}

        done_paging?(ack, records, end_dt) ->
          {:ok, merged}

        true ->
          next_range = next_range(ack, range)

          if next_range == range do
            {:ok, merged}
          else
            fetch_pages(device_id, object_id, next_range, start_dt, end_dt, merged)
          end
      end
    end
  end

  defp done_paging?(%ReadRangeAck{result_flags: flags, item_count: count}, records, end_dt) do
    not flags.more_items or count == 0 or records == [] or
      past_end?(List.last(records), end_dt)
  end

  defp past_end?(%{timestamp: timestamp}, end_dt) do
    case BACnetDateTime.to_naive_datetime(timestamp) do
      {:ok, at} -> NaiveDateTime.compare(at, end_dt) == :gt
      _end_dt -> false
    end
  end

  defp past_end?(_end_dt, _past_end2), do: false

  defp next_range(%ReadRangeAck{item_count: count} = ack, {:by_time, _nil}) do
    next_seq_range(ack, count)
  end

  defp next_range(%ReadRangeAck{item_count: count} = ack, {:by_seq_number, _nil}) do
    next_seq_range(ack, count)
  end

  defp next_range(%ReadRangeAck{item_count: count} = ack, nil) do
    next_seq_range(ack, count)
  end

  defp next_seq_range(%ReadRangeAck{} = ack, count) do
    case {first_sequence_number(ack), count} do
      {seq, count} when is_integer(seq) and is_integer(count) and count > 0 ->
        {:by_seq_number, {seq + count, @page_size}}

      _count ->
        nil
    end
  end

  defp first_sequence_number(%ReadRangeAck{first_sequence_number: seq}) when is_integer(seq),
    do: seq

  defp first_sequence_number(_seq), do: nil

  @doc false
  @spec decode_records(ObjectIdentifier.t(), [Encoding.t()]) ::
          {:ok, [map()]} | {:error, term()}
  def decode_records(%ObjectIdentifier{} = object_id, item_data) when is_list(item_data) do
    case ObjectsUtility.cast_property_to_value(object_id, :log_buffer, item_data) do
      {:ok, records} when is_list(records) ->
        {:ok, Enum.map(records, &normalize_record/1)}

      {:ok, record} ->
        {:ok, [normalize_record(record)]}

      {:error, _item_data} = err ->
        err
    end
  end

  def decode_records(_object_id, []), do: {:ok, []}

  defp normalize_record(%LogRecord{} = record) do
    %{
      type: :log_record,
      timestamp: record.timestamp,
      datum: record.log_datum,
      status_flags: record.status_flags
    }
  end

  defp normalize_record(%LogMultipleRecord{} = record) do
    %{
      type: :log_multiple_record,
      timestamp: record.timestamp,
      data: record.log_data
    }
  end

  defp normalize_record(other), do: other

  @doc false
  @spec records_for_range([map()], :all | {NaiveDateTime.t(), NaiveDateTime.t()}) :: [map()]
  def records_for_range(records, :all) when is_list(records), do: records

  def records_for_range(records, {start_dt, end_dt}) when is_list(records) do
    filter_records(records, start_dt, end_dt)
  end

  @doc false
  @spec filter_records([map()], NaiveDateTime.t(), NaiveDateTime.t()) :: [map()]
  def filter_records(records, start_dt, end_dt) when is_list(records) do
    Enum.filter(records, fn record ->
      case record_timestamp(record) do
        {:ok, at} ->
          NaiveDateTime.compare(at, start_dt) != :lt and NaiveDateTime.compare(at, end_dt) != :gt

        _records ->
          false
      end
    end)
  end

  @doc false
  @spec record_timestamp(map()) :: {:ok, NaiveDateTime.t()} | :error
  def record_timestamp(%{timestamp: %BACnetDateTime{} = timestamp}) do
    case BACnetDateTime.to_naive_datetime(timestamp) do
      {:ok, %NaiveDateTime{} = at} -> {:ok, at}
      _record_timestamp -> :error
    end
  end

  def record_timestamp(_record_timestamp), do: :error

  @doc false
  @spec plottable_value?(term()) :: boolean()
  def plottable_value?(%Encoding{}), do: true
  def plottable_value?(value) when is_number(value), do: true
  def plottable_value?(value) when is_boolean(value), do: true
  def plottable_value?(_value), do: false

  @doc false
  @spec marker_kind(term()) :: atom() | nil
  def marker_kind(%LogStatus{buffer_purged: true}), do: :buffer_purged
  def marker_kind(%LogStatus{log_disabled: true}), do: :log_disabled
  def marker_kind(%LogStatus{log_interrupted: true}), do: :log_interrupted
  def marker_kind(%LogStatus{}), do: :log_status
  def marker_kind(%BACnetError{}), do: :read_error
  def marker_kind({:time_change, _marker_kind}), do: :time_change
  def marker_kind(_marker_kind), do: nil

  @doc false
  @spec numeric_value(term()) :: {:ok, float()} | :error
  def numeric_value(%Encoding{type: :real, value: value}) when is_number(value),
    do: {:ok, value * 1.0}

  def numeric_value(%Encoding{type: :boolean, value: value}) when is_boolean(value),
    do: {:ok, if(value, do: 1.0, else: 0.0)}

  def numeric_value(%Encoding{type: :enumerated, value: value}) when is_integer(value),
    do: {:ok, value * 1.0}

  def numeric_value(%Encoding{type: :unsigned_integer, value: value}) when is_integer(value),
    do: {:ok, value * 1.0}

  def numeric_value(%Encoding{type: :signed_integer, value: value}) when is_integer(value),
    do: {:ok, value * 1.0}

  def numeric_value(value) when is_number(value), do: {:ok, value * 1.0}
  def numeric_value(value) when is_boolean(value), do: {:ok, if(value, do: 1.0, else: 0.0)}
  def numeric_value(_value), do: :error
end
