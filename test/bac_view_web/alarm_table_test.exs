defmodule BacViewWeb.AlarmTableTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.StatusFlags
  alias BacViewWeb.AlarmTable

  test "sorted_events sorts by updated_at" do
    older = %{
      object_id: %ObjectIdentifier{type: :analog_input, instance: 1},
      event_state: :normal,
      notify_type: :alarm,
      updated_at: ~U[2024-01-01 10:00:00Z]
    }

    newer = %{
      object_id: %ObjectIdentifier{type: :analog_input, instance: 2},
      event_state: :fault,
      notify_type: :alarm,
      updated_at: ~U[2024-01-02 10:00:00Z]
    }

    assert [^newer, ^older] = AlarmTable.sorted_events([older, newer], "updated_at", :desc)
  end

  test "sorted_active_alarms sorts by alarm since" do
    flags = %StatusFlags{
      in_alarm: false,
      fault: false,
      overridden: false,
      out_of_service: false
    }

    older = %{
      type: :analog_input,
      instance: 1,
      name: "A",
      status_flags: flags,
      alarm_since_sort_key: 100
    }

    newer = %{
      type: :analog_input,
      instance: 2,
      name: "B",
      status_flags: flags,
      alarm_since_sort_key: 200
    }

    assert [^newer, ^older] =
             AlarmTable.sorted_active_alarms([older, newer], "alarm_since", :desc)
  end

  test "sorted_active_alarms sorts by object id" do
    flags = %StatusFlags{
      in_alarm: false,
      fault: false,
      overridden: false,
      out_of_service: false
    }

    a = %{type: :binary_input, instance: 2, name: "B", status_flags: flags}
    b = %{type: :analog_input, instance: 1, name: "A", status_flags: flags}

    assert [^b, ^a] = AlarmTable.sorted_active_alarms([a, b], "object_id", :asc)
  end

  test "sorted_notifications sorts by priority" do
    low = %{priority: 50, object_id: %ObjectIdentifier{type: :analog_input, instance: 1}}
    high = %{priority: 10, object_id: %ObjectIdentifier{type: :analog_input, instance: 2}}

    assert [^high, ^low] = AlarmTable.sorted_notifications([low, high], "priority", :asc)
  end
end
