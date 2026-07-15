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

  @doc "Converts a naive wall-clock datetime to UTC unix milliseconds using the application timezone."
  @spec naive_to_unix_ms(NaiveDateTime.t()) :: integer()
  def naive_to_unix_ms(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!(name())
    |> DateTime.to_unix(:millisecond)
  end

  @doc "Converts UTC unix milliseconds to naive wall-clock in the application timezone."
  @spec unix_ms_to_naive(integer()) :: NaiveDateTime.t()
  def unix_ms_to_naive(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> shift()
    |> DateTime.to_naive()
  end
end
