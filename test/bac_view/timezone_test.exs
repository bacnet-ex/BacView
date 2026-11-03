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

  test "naive_to_unix_ms/1 uses the earlier instant when the wall clock repeats" do
    assert Timezone.name() == "Europe/Zurich"

    naive = ~N[2026-10-25 02:00:00.910000]
    {:ambiguous, earlier, later} = DateTime.from_naive(naive, Timezone.name())

    assert Timezone.wall_instants(naive) ==
             {:ambiguous, DateTime.to_unix(earlier, :millisecond),
              DateTime.to_unix(later, :millisecond)}

    assert Timezone.naive_to_unix_ms(naive) == DateTime.to_unix(earlier, :millisecond)

    assert DateTime.to_unix(later, :millisecond) - DateTime.to_unix(earlier, :millisecond) ==
             3_600_000
  end

  test "naive_to_unix_ms/1 uses the first valid instant after a spring-forward gap" do
    assert Timezone.name() == "Europe/Zurich"

    naive = ~N[2026-03-29 02:30:00]
    {:gap, _just_before, just_after} = DateTime.from_naive(naive, Timezone.name())
    ms = DateTime.to_unix(just_after, :millisecond)

    assert Timezone.wall_instants(naive) == {:gap, ms}
    assert Timezone.naive_to_unix_ms(naive) == ms
  end
end
