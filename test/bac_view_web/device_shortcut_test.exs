defmodule BacViewWeb.DeviceShortcutTest do
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

  test "r shortcut reloads device on device page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/devices/42")

    html =
      render_click(view, "global_keydown", %{"key" => "r", "code" => "KeyR", "shift" => false})

    assert html =~ ~s(id="device-refresh-banner")
    refute html =~ ~s(id="device-load-progress")
    assert has_element?(view, "#device-refresh-btn[disabled]")
    assert has_element?(view, "#device-refresh-btn .animate-spin")
  end
end
