defmodule BacView.BACnet.SubscriptionManagerBulkTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.SubscriptionManager
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_devices, [:named_table, :set, :public]},
    {:bacview_subscriptions, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_cov_notification_log, [:named_table, :ordered_set, :public]},
    {:bacview_cov_notification_seq, [:named_table, :set, :public]}
  ]

  defmodule SlowCovClient do
    @moduledoc false
    def subscribe_cov_property(_destination, _object, _property, _opts) do
      Process.sleep(120)
      :ok
    end

    def subscribe_cov(_destination, _object, _opts) do
      Process.sleep(120)
      :ok
    end
  end

  defmodule FastCovClient do
    @moduledoc false
    def subscribe_cov_property(_destination, _object, _property, _opts), do: :ok
    def subscribe_cov(_destination, _object, _opts), do: :ok
  end

  setup do
    previous_client = Application.get_env(:bacview, :cov_client)

    pid =
      case Process.whereis(SubscriptionManager) do
        nil -> start_supervised!(SubscriptionManager)
        running -> running
      end

    on_exit(fn ->
      Application.put_env(:bacview, :cov_client, previous_client)
    end)

    {:ok, manager: pid}
  end

  test "bulk_subscribe returns before Subscribe-COV jobs finish" do
    BacnetEtsLock.with_tables(@tables, fn ->
      Application.put_env(:bacview, :cov_client, SlowCovClient)
      insert_device(42)

      targets =
        Enum.map(1..4, fn instance ->
          {%ObjectIdentifier{type: :analog_input, instance: instance}, :present_value}
        end)

      started = System.monotonic_time(:millisecond)
      assert :ok = SubscriptionManager.bulk_subscribe(42, targets, self(), action: :subscribe)
      elapsed = System.monotonic_time(:millisecond) - started

      assert elapsed < 80

      assert_receive {:cov_bulk_progress, _done, 4}, 1_000
      assert_receive {:cov_bulk_done, result}, 2_000
      assert result.action == :subscribe
      assert result.ok == 4
      assert result.failed == 0
      assert result.total == 4
    end)
  end

  test "bulk_unsubscribe reports counts without blocking the caller" do
    BacnetEtsLock.with_tables(@tables, fn ->
      Application.put_env(:bacview, :cov_client, FastCovClient)
      insert_device(42)

      object_id = %ObjectIdentifier{type: :analog_input, instance: 1}
      assert :ok = SubscriptionManager.subscribe(42, object_id, :present_value)
      assert SubscriptionManager.subscribed?(42, object_id, :present_value)

      assert :ok =
               SubscriptionManager.bulk_unsubscribe(
                 42,
                 [{object_id, :present_value}],
                 self(),
                 action: :unsubscribe_all
               )

      assert_receive {:cov_bulk_done, result}, 1_000
      assert result.action == :unsubscribe_all
      assert result.ok == 1
      refute SubscriptionManager.subscribed?(42, object_id, :present_value)
    end)
  end

  defp insert_device(id) do
    :ets.insert(
      :bacview_devices,
      {id,
       %{
         id: id,
         instance: id,
         address: {{192, 168, 1, 10}, 47_808},
         ip: "192.168.1.10",
         port: 47_808,
         name: "Test Device"
       }}
    )
  end
end
