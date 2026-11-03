defmodule BacViewWeb.CovSubscriptionExportLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PriorityArray
  alias BacView.BACnet.Subscription
  alias BacView.Test.BacnetEtsLock

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

  @tables [
    {:bacview_devices, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_subscriptions, [:named_table, :set, :public, read_concurrency: true]},
    {:bacview_cov_notification_log,
     [:named_table, :ordered_set, :public, read_concurrency: true]},
    {:bacview_properties, [:named_table, :set, :public, read_concurrency: true]}
  ]

  test "exports selected COV notifications as CSV and JSON", %{conn: conn} do
    BacnetEtsLock.with_tables(@tables, fn ->
      :ets.insert(:bacview_devices, {42, @device})

      object_id = %ObjectIdentifier{type: :analog_output, instance: 3}
      array = %PriorityArray{priority_8: 21.5}
      insert_subscription(object_id, :priority_array, array)
      insert_notification(object_id, :priority_array, array, "21.5 (P8)")

      {:ok, view, _html} = live(conn, ~p"/devices/42?tab=subscriptions")
      send(view.pid, {:device_load_done, {:ok, loaded_device()}})
      assert has_element?(view, "#sub-42-analog_output-3-priority_array")
      refute has_element?(view, "#cov-chart-open-analog_output-3-priority_array")

      render_click(view, "toggle_subscription_selection", %{
        "type" => "analog_output",
        "instance" => "3",
        "property" => "priority_array"
      })

      assert has_element?(view, "#export-selected-subscriptions-csv")
      assert has_element?(view, "#export-selected-subscriptions-menu")

      render_click(view, "export_selected_subscriptions", %{"format" => "csv"})

      assert_push_event(view, "download_file", %{
        filename: "bacview-cov-analog_output-3-priority_array.csv",
        mime: "text/csv; charset=utf-8",
        content: csv
      })

      assert csv =~ "timestamp;"
      assert csv =~ "Zuluftklappe (analog_output:3 priority array)"
      assert csv =~ "8: 21.5"
      assert csv =~ "1: NULL"
      assert has_element?(view, "#subscription-selection-bar")

      render_click(view, "export_selected_subscriptions", %{"format" => "json"})

      assert_push_event(view, "download_file", %{
        filename: "bacview-cov-analog_output-3-priority_array.json",
        mime: "application/json; charset=utf-8",
        content: json
      })

      decoded = Jason.decode!(json)
      assert decoded["device_id"] == 42
      assert [entry] = decoded["notifications"]
      assert entry["object_name"] == "Zuluftklappe"
      assert entry["property"] == "priority_array"
      assert length(entry["value"]) == 16
      assert Enum.at(entry["value"], 7) == %{"priority" => 8, "value" => 21.5}
    end)
  end

  test "reports when the selection has no COV notifications", %{conn: conn} do
    BacnetEtsLock.with_tables(@tables, fn ->
      :ets.insert(:bacview_devices, {42, @device})

      object_id = %ObjectIdentifier{type: :analog_output, instance: 3}
      insert_subscription(object_id, :priority_array, %PriorityArray{})

      {:ok, view, _html} = live(conn, ~p"/devices/42?tab=subscriptions")
      send(view.pid, {:device_load_done, {:ok, loaded_device()}})

      render_click(view, "toggle_subscription_selection", %{
        "type" => "analog_output",
        "instance" => "3",
        "property" => "priority_array"
      })

      html = render_click(view, "export_selected_subscriptions", %{"format" => "csv"})

      assert html =~ "Keine COV-Meldungen für die Auswahl."
    end)
  end

  defp insert_subscription(object_id, property, value) do
    key = Subscription.key(42, object_id, property)

    sub = %{
      device_id: 42,
      destination: nil,
      object_id: object_id,
      property: property,
      process_id: 1,
      lifetime: 3600,
      confirmed: false,
      cov_increment: nil,
      subscribe_service: :subscribe_cov_property,
      subscribed_at: ~U[2026-03-15 10:00:00Z],
      expires_at: ~U[2026-03-15 11:00:00Z],
      last_cov_at: ~U[2026-03-15 10:30:00Z],
      last_value: value,
      last_value_formatted: "21.5 (P8)",
      time_remaining: 1800,
      status: :active
    }

    :ets.insert(:bacview_subscriptions, {key, sub})
  end

  defp insert_notification(object_id, property, value, formatted) do
    received_at = ~U[2026-03-15 10:30:00Z]
    micro = DateTime.to_unix(received_at, :microsecond)

    entry = %{
      device_id: 42,
      object_id: object_id,
      property: property,
      value: value,
      formatted: formatted,
      confirmed: false,
      time_remaining: 1800,
      received_at: received_at,
      log_id: 1
    }

    key = {42, object_id.type, object_id.instance, property, -micro, 1}
    :ets.insert(:bacview_cov_notification_log, {key, entry})
  end

  defp loaded_device() do
    Map.merge(@device, %{
      objects: [
        %{
          type: :analog_output,
          instance: 3,
          name: "Zuluftklappe",
          description: "Zuluftklappe",
          present_value: 21.5,
          present_value_formatted: "21.5",
          commandable: true,
          writable: true,
          updated_at: nil
        }
      ],
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
