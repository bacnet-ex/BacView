defmodule BacView.BACnet.CacheTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Cache
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_devices, [:named_table, :set, :public]},
    {:bacview_objects, [:named_table, :set, :public]},
    {:bacview_properties, [:named_table, :set, :public]},
    {:bacview_hierarchy, [:named_table, :set, :public]},
    {:bacview_subscriptions, [:named_table, :set, :public]},
    {:bacview_events, [:named_table, :set, :public]},
    {:bacview_validation_skip_modes, [:named_table, :set, :public]},
    {:bacview_cov_notification_log, [:named_table, :ordered_set, :public]},
    {:bacview_nc_recipients, [:named_table, :set, :public]}
  ]

  test "clear_all_device_data empties owned and related tables" do
    BacnetEtsLock.with_tables(@tables, fn ->
      :ets.insert(:bacview_devices, {1, %{id: 1}})
      :ets.insert(:bacview_objects, {1, []})
      :ets.insert(:bacview_properties, {{1, :analog_input, 1}, []})
      :ets.insert(:bacview_hierarchy, {1, %{}})
      :ets.insert(:bacview_subscriptions, {{1, :analog_input, 1, :present_value}, %{}})
      :ets.insert(:bacview_events, {{1, :analog_input, 1}, %{}})
      :ets.insert(:bacview_validation_skip_modes, {{1, :analog_input, 1}, true})
      :ets.insert(:bacview_cov_notification_log, {{1, -1, 1}, %{}})
      :ets.insert(:bacview_nc_recipients, {{1, 0}, %{}})

      assert Cache.clear_all_device_data() == :ok

      assert :ets.tab2list(:bacview_devices) == []
      assert :ets.tab2list(:bacview_objects) == []
      assert :ets.tab2list(:bacview_properties) == []
      assert :ets.tab2list(:bacview_hierarchy) == []
      assert :ets.tab2list(:bacview_subscriptions) == []
      assert :ets.tab2list(:bacview_events) == []
      assert :ets.tab2list(:bacview_validation_skip_modes) == []
      assert :ets.tab2list(:bacview_cov_notification_log) == []
      assert :ets.tab2list(:bacview_nc_recipients) == []
    end)
  end
end
