defmodule BacView.Timezone do
  @moduledoc false

  @default "Europe/Zurich"

  @doc "Returns the configured application timezone (IANA name)."
  @spec name() :: Calendar.time_zone()
  def name() do
    Application.get_env(:bacview, :timezone, @default)
  end

  @doc "Shifts a DateTime to the application timezone."
  @spec shift(DateTime.t()) :: DateTime.t()
  def shift(%DateTime{} = dt) do
    DateTime.shift_zone!(dt, name())
  end

  @doc "Formats a DateTime in the application timezone."
  @spec format(DateTime.t() | nil, String.t()) :: String.t()
  def format(nil, _pattern), do: "-"

  def format(%DateTime{} = dt, pattern) do
    dt
    |> shift()
    |> Calendar.strftime(pattern)
  end

  @doc "Returns the current time in the application timezone."
  @spec now() :: DateTime.t()
  def now(), do: DateTime.now!(name())

  @doc """
  Converts a naive wall-clock datetime to UTC unix milliseconds in the application timezone.

  A repeated wall time, from the daylight-saving fallback overlap, uses the earlier
  instant. A skipped wall time, from the spring-forward gap, uses the first valid
  instant after the gap.
  """
  @spec naive_to_unix_ms(NaiveDateTime.t()) :: integer()
  def naive_to_unix_ms(%NaiveDateTime{} = naive) do
    case wall_instants(naive) do
      {:ok, ms} ->
        ms

      {:ambiguous, earlier_ms, _later_ms} ->
        earlier_ms

      {:gap, ms} ->
        ms

      {:error, reason} ->
        raise ArgumentError,
              "cannot convert #{inspect(naive)} in time zone #{name()}: #{inspect(reason)}"
    end
  end

  @doc """
  Classifies a wall-clock time in the application timezone.

  Returns `{:ambiguous, earlier_ms, later_ms}` for the repeated hour when daylight
  saving ends. `earlier_ms` is the first time the clock shows that wall time.
  Returns `{:gap, ms}` for the skipped hour when daylight saving starts, where `ms`
  is the first valid instant after the gap.
  """
  @spec wall_instants(NaiveDateTime.t()) ::
          {:ok, integer()}
          | {:ambiguous, integer(), integer()}
          | {:gap, integer()}
          | {:error, term()}
  def wall_instants(%NaiveDateTime{} = naive) do
    case DateTime.from_naive(naive, name()) do
      {:ok, datetime} ->
        {:ok, unix_ms(datetime)}

      {:ambiguous, earlier, later} ->
        {:ambiguous, unix_ms(earlier), unix_ms(later)}

      {:gap, _just_before, just_after} ->
        {:gap, unix_ms(just_after)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unix_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)

  @doc "Converts UTC unix milliseconds to naive wall-clock in the application timezone."
  @spec unix_ms_to_naive(integer()) :: NaiveDateTime.t()
  def unix_ms_to_naive(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> shift()
    |> DateTime.to_naive()
  end
end
