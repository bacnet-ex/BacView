defmodule BacViewWeb.DeviceCovBulkLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier

  @device %{
    id: 42,
    instance: 42,
    address: {{192, 168, 1, 10}, 47_808},
    ip: "192.168.1.10",
    port: 47_808,
    max_apdu: 480,
    segmentation: 0,
    vendor_id: 5,
    object: %ObjectIdentifier{type: :device, instance: 42},
    status: :discovered,
    object_count: nil,
    name: "Test Device",
    loaded_at: nil,
    discovered_at: DateTime.utc_now()
  }

  defmodule SlowCovClient do
    @moduledoc false
    def subscribe_cov_property(_destination, _object, _property, _opts) do
      Process.sleep(200)
      :ok
    end

    def subscribe_cov(_destination, _object, _opts) do
      Process.sleep(200)
      :ok
    end
  end

  setup do
    previous_client = Application.get_env(:bacview, :cov_client)
    Application.put_env(:bacview, :cov_client, SlowCovClient)

    unless :ets.whereis(:bacview_devices) != :undefined do
      :ets.new(:bacview_devices, [:named_table, :set, :public, read_concurrency: true])
    end

    :ets.insert(:bacview_devices, {42, @device})

    case Process.whereis(BacView.BACnet.SubscriptionManager) do
      nil -> start_supervised!(BacView.BACnet.SubscriptionManager)
      _pid -> :ok
    end

    on_exit(fn ->
      Application.put_env(:bacview, :cov_client, previous_client)

      if :ets.whereis(:bacview_devices) != :undefined do
        :ets.delete_all_objects(:bacview_devices)
      end
    end)

    :ok
  end

  test "subscribe all PV does not block tab patches", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/42?tab=objects")
    send(view.pid, {:device_load_done, {:ok, loaded_device()}})
    assert has_element?(view, "#object-analog_input-1")

    started = System.monotonic_time(:millisecond)
    html = render_click(view, "subscribe_all_pv")
    assert html =~ ~s(id="cov-bulk-progress")

    render_patch(view, ~p"/devices/42?tab=subscriptions")
    elapsed = System.monotonic_time(:millisecond) - started

    assert has_element?(view, "#device-tab-subscriptions")
    assert has_element?(view, "#cov-bulk-progress")
    assert elapsed < 400
  end

  test "COV progress and notification bursts do not delay tab patches", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/42?tab=objects")
    send(view.pid, {:device_load_done, {:ok, loaded_device()}})
    assert has_element?(view, "#object-analog_input-1")

    send(view.pid, {:cov_bulk_progress, 1, 80})

    Enum.each(2..80, fn idx ->
      send(view.pid, {:cov_bulk_progress, idx, 80})
      send(view.pid, :cov_updated)
      send(view.pid, {:cov_notification, %{log_id: idx}})
    end)

    started = System.monotonic_time(:millisecond)
    render_patch(view, ~p"/devices/42?tab=alarms")
    elapsed = System.monotonic_time(:millisecond) - started

    assert has_element?(view, "#device-tab-alarms")
    assert elapsed < 400
  end

  defp loaded_device do
    objects =
      Enum.map(1..3, fn instance ->
        %{
          type: :analog_input,
          instance: instance,
          name: "AI-#{instance}",
          present_value: instance * 1.0,
          present_value_formatted: "#{instance}.0",
          description: nil,
          commandable: false,
          writable: false,
          updated_at: nil
        }
      end)

    Map.merge(@device, %{
      objects: objects,
      hierarchy: %{
        roots: [],
        empty?: true,
        structured_view_count: 0,
        source: :structured,
        split: nil
      },
      from_cache: true
    })
  end
end
