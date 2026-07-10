defmodule BacView.TimezoneTest do
  use ExUnit.Case, async: true

  alias BacView.Timezone

  test "name/0 returns configured timezone" do
    assert Timezone.name() == Application.get_env(:bacview, :timezone, "Europe/Zurich")
  end

  test "format/2 shifts UTC timestamps to the application timezone" do
    utc = ~U[2026-07-10 11:33:40Z]

    assert Timezone.format(utc, "%H:%M:%S") == "13:33:40"
  end

  test "naive_to_unix_ms/1 and unix_ms_to_naive/1 round-trip wall-clock values" do
    naive = ~N[2025-03-15 18:28:00]
    ms = Timezone.naive_to_unix_ms(naive)

    assert NaiveDateTime.truncate(Timezone.unix_ms_to_naive(ms), :second) == naive
  end
end
