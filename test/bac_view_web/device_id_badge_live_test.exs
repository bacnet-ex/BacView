defmodule BacViewWeb.DeviceIdBadgeLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @device %{
    id: 42,
    instance: 42,
    address: {{192, 168, 1, 10}, 47_808},
    ip: "192.168.1.10",
    port: 47_808,
    max_apdu: 480,
    segmentation: 0,
    vendor_id: 5,
    object: %BACnet.Protocol.ObjectIdentifier{type: :device, instance: 42},
    status: :discovered,
    object_count: nil,
    name: "Test Device",
    loaded_at: nil,
    discovered_at: DateTime.utc_now()
  }

  @device_with_npci Map.put(@device, :npci_source, %BACnet.Protocol.NpciTarget{
                      net: 3,
                      address: 200
                    })

  setup do
    unless :ets.whereis(:bacview_devices) != :undefined do
      :ets.new(:bacview_devices, [:named_table, :set, :public, read_concurrency: true])
    end

    :ets.insert(:bacview_devices, {42, @device})

    on_exit(fn ->
      if :ets.whereis(:bacview_devices) != :undefined do
        :ets.delete_all_objects(:bacview_devices)
      end
    end)

    :ok
  end

  test "device page header shows device ID badge", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/42")

    assert has_element?(view, "#device-id-badge", "ID 42")
  end

  test "device page header shows NPCI source indicator when present", %{conn: conn} do
    :ets.insert(:bacview_devices, {42, @device_with_npci})

    {:ok, view, html} = live(conn, ~p"/devices/42")

    assert has_element?(view, "#device-npci-source")
    assert html =~ "NPCI-Quelle: 3/200"
  end

  test "device page header omits NPCI source indicator when absent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/42")

    refute has_element?(view, "#device-npci-source")
  end
end
