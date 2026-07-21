defmodule BacView.LogStoreTest do
  use ExUnit.Case, async: false

  alias BacView.LogStore
  alias BacView.LogStore.Handler

  setup do
    LogStore.clear()
    :ok
  end

  test "ingest and list entries" do
    :ok =
      LogStore.ingest(%{
        level: :info,
        message: "hello log",
        time: DateTime.utc_now(),
        metadata: %{}
      })

    # cast is async
    :timer.sleep(20)

    entries = LogStore.list()
    assert Enum.any?(entries, &(&1.message == "hello log"))
  end

  test "clear empties buffer" do
    LogStore.ingest(%{level: :warning, message: "warn", time: DateTime.utc_now(), metadata: %{}})
    :timer.sleep(20)
    assert LogStore.list() != []
    assert :ok = LogStore.clear()
    assert LogStore.list() == []
  end

  test "level filter keeps higher levels" do
    LogStore.ingest(%{level: :debug, message: "d", time: DateTime.utc_now(), metadata: %{}})
    LogStore.ingest(%{level: :error, message: "e", time: DateTime.utc_now(), metadata: %{}})
    :timer.sleep(20)

    entries = LogStore.list(level: :error)
    assert Enum.all?(entries, &(&1.level == :error))
  end

  test "logger handler treats meta time as system microseconds" do
    # ~ 2026-07-21 18:00:00 UTC
    us = 1_784_657_600_000_000

    assert :ok =
             Handler.log(
               %{
                 level: :info,
                 msg: {:string, "ts check"},
                 meta: %{time: us}
               },
               %{}
             )

    :timer.sleep(20)

    entry = Enum.find(LogStore.list(), &(&1.message == "ts check"))
    assert entry
    assert entry.time.year == 2026
    assert entry.time.month == 7
    assert entry.time.day == 21
    assert entry.time.hour == 18
  end
end
