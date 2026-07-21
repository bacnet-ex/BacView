defmodule BacView.LogStore.Handler do
  @moduledoc false

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_msg(msg)
    time = meta_time(meta)

    BacView.LogStore.ingest(%{
      level: level,
      message: message,
      time: time,
      metadata: %{
        mfa: Map.get(meta, :mfa),
        application: Map.get(meta, :application),
        module: Map.get(meta, :module)
      }
    })

    :ok
  rescue
    _error -> :ok
  end

  defp format_msg({:string, chardata}), do: IO.chardata_to_string(chardata)
  defp format_msg({:report, report}), do: inspect(report, limit: 50)
  defp format_msg(other), do: inspect(other, limit: 50)

  # OTP Logger timestamps are system time in **microseconds**
  # (erlang:system_time(microsecond)), not native time units.
  defp meta_time(%{time: time}) when is_integer(time) and time > 0 do
    case DateTime.from_unix(time, :microsecond) do
      {:ok, dt} -> DateTime.truncate(dt, :millisecond)
      _error -> DateTime.utc_now()
    end
  end

  defp meta_time(_meta), do: DateTime.utc_now()
end
