defmodule BacView.BACnet.DeviceRestartCovTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PropertyValue
  alias BACnet.Protocol.Services.UnconfirmedCovNotification
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.Subscription
  alias BacView.BACnet.SubscriptionManager
  alias BacView.Settings
  alias BacView.Test.BacnetEtsLock

  @tables [
    {:bacview_devices, [:named_table, :set, :public]},
    {:bacview_device_share, [:named_table, :set, :public]},
    {:bacview_subscriptions, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_cov_notification_log, [:named_table, :ordered_set, :public]},
    {:bacview_cov_notification_seq, [:named_table, :set, :public]}
  ]

  defmodule MockCovClient do
    @moduledoc false
    def subscribe_cov_property(_destination, object, _property, _opts) do
      case Process.get({:mock_cov_result, object}) do
        nil -> :ok
        result -> result
      end
    end

    def subscribe_cov(_destination, object, _opts) do
      case Process.get({:mock_cov_result, object}) do
        nil -> :ok
        result -> result
      end
    end
  end

  setup do
    previous_scan = Settings.get().scan_on_online
    previous_client = Application.get_env(:bacview, :cov_client)

    Application.put_env(:bacview, :cov_client, MockCovClient)
    assert {:ok, _} = Settings.update(scan_on_online: false)
    Discovery.set_acceptance_filters(low_limit: nil, high_limit: nil, vendor_id: nil)

    on_exit(fn ->
      Application.put_env(:bacview, :cov_client, previous_client)
      Discovery.set_acceptance_filters(low_limit: nil, high_limit: nil, vendor_id: nil)
      _result = Settings.update(scan_on_online: previous_scan)
    end)

    :ok
  end

  test "device_restart_cov_notification? matches device object with restart properties" do
    assert SubscriptionManager.device_restart_cov_notification?(restart_notif(100))
  end

  test "device_restart_cov_notification? accepts numeric property identifiers" do
    device = %ObjectIdentifier{type: :device, instance: 100}

    notif = %UnconfirmedCovNotification{
      process_identifier: 0,
      initiating_device: device,
      monitored_object: device,
      time_remaining: 0,
      property_values: [
        %PropertyValue{
          property_identifier: 112,
          property_array_index: nil,
          property_value: {:enumerated, 0},
          priority: nil
        },
        %PropertyValue{
          property_identifier: 203,
          property_array_index: nil,
          property_value: {:null, nil},
          priority: nil
        },
        %PropertyValue{
          property_identifier: 196,
          property_array_index: nil,
          property_value: {:enumerated, 1},
          priority: nil
        }
      ]
    }

    assert SubscriptionManager.device_restart_cov_notification?(notif)
  end

  test "device_restart_cov_notification? rejects incomplete property set" do
    device = %ObjectIdentifier{type: :device, instance: 100}

    notif = %UnconfirmedCovNotification{
      process_identifier: 0,
      initiating_device: device,
      monitored_object: device,
      time_remaining: 0,
      property_values: [
        %PropertyValue{
          property_identifier: :system_status,
          property_array_index: nil,
          property_value: {:enumerated, 0},
          priority: nil
        }
      ]
    }

    refute SubscriptionManager.device_restart_cov_notification?(notif)
  end

  test "device_restart_cov_notification? rejects non-device monitored object" do
    device = %ObjectIdentifier{type: :device, instance: 100}
    ai = %ObjectIdentifier{type: :analog_input, instance: 1}

    notif = %UnconfirmedCovNotification{
      process_identifier: 0,
      initiating_device: device,
      monitored_object: ai,
      time_remaining: 0,
      property_values: restart_property_values()
    }

    refute SubscriptionManager.device_restart_cov_notification?(notif)
  end

  test "device_restart_cov_notification? rejects non-zero process identifier" do
    device = %ObjectIdentifier{type: :device, instance: 100}

    notif = %UnconfirmedCovNotification{
      process_identifier: 1,
      initiating_device: device,
      monitored_object: device,
      time_remaining: 0,
      property_values: restart_property_values()
    }

    refute SubscriptionManager.device_restart_cov_notification?(notif)
  end

  test "device_restart_cov_notification? rejects non-zero time remaining" do
    device = %ObjectIdentifier{type: :device, instance: 100}

    notif = %UnconfirmedCovNotification{
      process_identifier: 0,
      initiating_device: device,
      monitored_object: device,
      time_remaining: 60,
      property_values: restart_property_values()
    }

    refute SubscriptionManager.device_restart_cov_notification?(notif)
  end

  test "unknown_object_error? matches BACnet unknown_object errors" do
    assert SubscriptionManager.unknown_object_error?(
             {:bacnet_error,
              %APDU.Error{
                invoke_id: 1,
                service: :subscribe_cov_property,
                class: :object,
                code: :unknown_object,
                payload: []
              }}
           )

    assert SubscriptionManager.unknown_object_error?(:unknown_object)
    refute SubscriptionManager.unknown_object_error?(:timeout)
  end

  test "apply_renew_result drops local subscription on unknown_object" do
    BacnetEtsLock.with_tables(@tables, fn ->
      object = %ObjectIdentifier{type: :analog_input, instance: 1}

      sub =
        Subscription.build(42, {{10, 0, 0, 1}, 47_808}, object, :present_value,
          lifetime: 3600,
          process_id: 7
        )

      key = Subscription.key(42, object, :present_value)
      :ets.insert(:bacview_subscriptions, {key, sub})
      assert SubscriptionManager.subscribed?(42, object, :present_value)

      assert :ok =
               SubscriptionManager.apply_renew_result(
                 sub,
                 {:error,
                  {:bacnet_error,
                   %APDU.Error{
                     invoke_id: 1,
                     service: :subscribe_cov_property,
                     class: :object,
                     code: :unknown_object,
                     payload: []
                   }}}
               )

      refute SubscriptionManager.subscribed?(42, object, :present_value)
    end)
  end

  test "apply_renew_result keeps subscription on other errors" do
    BacnetEtsLock.with_tables(@tables, fn ->
      object = %ObjectIdentifier{type: :analog_input, instance: 2}

      sub =
        Subscription.build(42, {{10, 0, 0, 1}, 47_808}, object, :present_value,
          lifetime: 3600,
          process_id: 7
        )

      key = Subscription.key(42, object, :present_value)
      :ets.insert(:bacview_subscriptions, {key, sub})

      log =
        capture_log(fn ->
          assert {:error, :timeout} =
                   SubscriptionManager.apply_renew_result(sub, {:error, :timeout})
        end)

      assert log =~ "BACnet cov_renew failed"
      assert log =~ "device 42"
      assert log =~ "analog_input:2"
      assert log =~ "present_value"
      assert SubscriptionManager.subscribed?(42, object, :present_value)
    end)
  end

  test "handle_device_restart_cov refreshes address and renews COV subscriptions" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_obj = %ObjectIdentifier{type: :device, instance: 55}
      old_address = {{10, 0, 0, 10}, 47_808}
      new_address = {{10, 0, 0, 11}, 47_808}
      ai = %ObjectIdentifier{type: :analog_input, instance: 3}
      gone = %ObjectIdentifier{type: :analog_input, instance: 99}

      # Known device — restart path only refreshes address (no Who-Is).
      :ets.insert(:bacview_devices, {
        55,
        %{
          id: 55,
          instance: 55,
          address: old_address,
          ip: "10.0.0.10",
          port: 47_808,
          address_label: "10.0.0.10:47808",
          object: device_obj,
          status: :discovered,
          vendor_id: 5,
          name: nil,
          object_count: nil,
          loaded_at: nil,
          discovered_at: DateTime.utc_now()
        }
      })

      keep_sub =
        Subscription.build(55, old_address, ai, :present_value, lifetime: 3600, process_id: 1)

      gone_sub =
        Subscription.build(55, old_address, gone, :present_value, lifetime: 3600, process_id: 1)

      :ets.insert(
        :bacview_subscriptions,
        {Subscription.key(55, ai, :present_value), keep_sub}
      )

      :ets.insert(
        :bacview_subscriptions,
        {Subscription.key(55, gone, :present_value), gone_sub}
      )

      Process.put({:mock_cov_result, gone}, {:error, :unknown_object})
      Process.put({:mock_cov_result, ai}, :ok)

      assert :ok =
               SubscriptionManager.handle_device_restart_cov(
                 restart_notif(55),
                 new_address,
                 async: false,
                 scan: false
               )

      assert {:ok, %{address: ^new_address}} = Discovery.get_device(55)
      assert SubscriptionManager.subscribed?(55, ai, :present_value)
      refute SubscriptionManager.subscribed?(55, gone, :present_value)

      # Renew should have rewritten the kept subscription against the new address.
      [active] = SubscriptionManager.list_active(55)
      assert active.destination == new_address
    end)
  end

  test "handle_device_restart_cov discovers unknown device via Who-Is probe" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_obj = %ObjectIdentifier{type: :device, instance: 70}
      address = {{10, 0, 0, 70}, 47_808}

      iam = %BACnet.Protocol.Services.IAm{
        device: device_obj,
        max_apdu: 1476,
        segmentation_supported: :segmented_both,
        vendor_id: 5
      }

      previous = Application.get_env(:bacview, :device_iam_probe)

      Application.put_env(:bacview, :device_iam_probe, fn instance, probe_addr ->
        assert instance == 70
        assert probe_addr == address
        {:ok, iam, address, nil, nil}
      end)

      on_exit(fn ->
        if previous do
          Application.put_env(:bacview, :device_iam_probe, previous)
        else
          Application.delete_env(:bacview, :device_iam_probe)
        end
      end)

      Discovery.set_acceptance_filters(vendor_id: 5)

      assert :ok =
               SubscriptionManager.handle_device_restart_cov(
                 restart_notif(70),
                 address,
                 async: false,
                 scan: false
               )

      assert {:ok, %{id: 70, vendor_id: 5, address: ^address}} = Discovery.get_device(70)
    end)
  end

  test "handle_device_restart_cov ignores non-restart COV" do
    BacnetEtsLock.with_tables(@tables, fn ->
      device_obj = %ObjectIdentifier{type: :device, instance: 66}
      address = {{10, 0, 0, 20}, 47_808}

      :ets.insert(:bacview_devices, {
        66,
        %{
          id: 66,
          instance: 66,
          address: address,
          ip: "10.0.0.20",
          port: 47_808,
          address_label: "10.0.0.20:47808",
          object: device_obj,
          status: :discovered,
          vendor_id: nil,
          name: nil,
          object_count: nil,
          loaded_at: nil,
          discovered_at: DateTime.utc_now()
        }
      })

      notif = %UnconfirmedCovNotification{
        process_identifier: 0,
        initiating_device: device_obj,
        monitored_object: device_obj,
        time_remaining: 0,
        property_values: [
          %PropertyValue{
            property_identifier: :system_status,
            property_array_index: nil,
            property_value: {:enumerated, 0},
            priority: nil
          }
        ]
      }

      assert :ok =
               SubscriptionManager.handle_device_restart_cov(notif, address,
                 async: false,
                 scan: false
               )

      assert {:ok, %{address: ^address}} = Discovery.get_device(66)
    end)
  end

  defp restart_notif(instance) do
    device = %ObjectIdentifier{type: :device, instance: instance}

    %UnconfirmedCovNotification{
      process_identifier: 0,
      initiating_device: device,
      monitored_object: device,
      time_remaining: 0,
      property_values: restart_property_values()
    }
  end

  defp restart_property_values do
    [
      %PropertyValue{
        property_identifier: :system_status,
        property_array_index: nil,
        property_value: {:enumerated, 0},
        priority: nil
      },
      %PropertyValue{
        property_identifier: :time_of_device_restart,
        property_array_index: nil,
        property_value: {:null, nil},
        priority: nil
      },
      %PropertyValue{
        property_identifier: :last_restart_reason,
        property_array_index: nil,
        property_value: {:enumerated, 1},
        priority: nil
      }
    ]
  end
end
