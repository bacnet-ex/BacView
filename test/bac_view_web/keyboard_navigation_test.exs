defmodule BacViewWeb.KeyboardNavigationTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.Shortcuts

  test "digit_index maps physical digit codes" do
    assert Shortcuts.digit_index("Digit1") == 1
    assert Shortcuts.digit_index("Digit4") == 4
    assert Shortcuts.digit_index("Digit5") == nil
    assert Shortcuts.digit_index("") == nil
  end

  test "shift_pressed? reads shift flag from keydown params" do
    assert Shortcuts.shift_pressed?(%{"shift" => true})
    refute Shortcuts.shift_pressed?(%{"shift" => false})
    refute Shortcuts.shift_pressed?(%{})
  end

  test "refresh_key? matches r and R" do
    assert Shortcuts.refresh_key?("r")
    assert Shortcuts.refresh_key?("R")
    refute Shortcuts.refresh_key?("t")
  end

  test "go_up_pressed? matches physical 0 key across layouts" do
    assert Shortcuts.go_up_pressed?(%{"key" => "0", "code" => "Digit0", "shift" => false})
    assert Shortcuts.go_up_pressed?(%{"key" => "0", "code" => "", "shift" => false})
    refute Shortcuts.go_up_pressed?(%{"key" => "0", "code" => "Digit0", "shift" => true})
    refute Shortcuts.go_up_pressed?(%{"key" => "§", "code" => "Digit3", "shift" => false})
  end

  test "letter_key_pressed? matches key and code" do
    assert Shortcuts.letter_key_pressed?(%{"key" => "c", "code" => "KeyC"}, "c")
    assert Shortcuts.letter_key_pressed?(%{"key" => "C", "code" => "KeyC"}, "c")
    assert Shortcuts.letter_key_pressed?(%{"key" => "u", "code" => "KeyU"}, "u")
    refute Shortcuts.letter_key_pressed?(%{"key" => "r", "code" => "KeyR"}, "c")
  end

  test "device_action routes tab-specific subscription shortcuts" do
    base = %{
      tab: "objects",
      cov_view: "subscriptions",
      alarm_view: "active_alarms",
      loading: false,
      bulk_subscribing: false,
      alarms_refreshing: false,
      nc_subscribing: false,
      nc_enrolled_count: 0,
      nc_total: 2,
      selected_object_keys: MapSet.new([{:analog_input, 1}]),
      selected_subscription_keys: MapSet.new([{:analog_input, 1, :present_value}]),
      subscriptions: [%{object_id: %{type: :analog_input, instance: 1}, property: :present_value}]
    }

    c = %{"key" => "c", "code" => "KeyC", "shift" => false}
    shift_c = %{"key" => "C", "code" => "KeyC", "shift" => true}
    u = %{"key" => "u", "code" => "KeyU", "shift" => false}
    shift_u = %{"key" => "U", "code" => "KeyU", "shift" => true}
    e = %{"key" => "e", "code" => "KeyE", "shift" => false}

    assert Shortcuts.device_action(c, base) == {:event, "subscribe_selected_cov"}
    assert Shortcuts.device_action(u, base) == {:event, "unsubscribe_selected_cov"}
    assert Shortcuts.device_action(shift_c, base) == {:event, "subscribe_all_pv"}
    assert Shortcuts.device_action(shift_u, base) == {:event, "unsubscribe_all_cov"}

    cov = %{base | tab: "subscriptions"}
    assert Shortcuts.device_action(c, cov) == {:event, "resubscribe_selected_subscriptions"}
    assert Shortcuts.device_action(shift_c, cov) == {:event, "subscribe_all_pv"}
    assert Shortcuts.device_action(u, cov) == {:event, "unsubscribe_selected_subscriptions"}
    assert Shortcuts.device_action(shift_u, cov) == {:event, "unsubscribe_all_cov"}

    alarms = %{base | tab: "alarms", nc_enrolled_count: 1}
    assert Shortcuts.device_action(c, alarms) == {:event, "subscribe_notification_classes"}
    assert Shortcuts.device_action(u, alarms) == {:event, "unsubscribe_notification_classes"}

    events = %{base | tab: "alarms", alarm_view: "event_information"}
    assert Shortcuts.device_action(e, events) == {:event, "refresh_alarms"}

    no_subs = %{base | subscriptions: []}
    assert Shortcuts.device_action(shift_u, no_subs) == :none
  end

  test "device_action ignores shortcuts outside their list context" do
    assigns = %{
      tab: "hierarchy",
      cov_view: "subscriptions",
      alarm_view: "active_alarms",
      loading: false,
      bulk_subscribing: false,
      alarms_refreshing: false,
      nc_subscribing: false,
      nc_enrolled_count: 0,
      nc_total: 2,
      selected_object_keys: MapSet.new([{:analog_input, 1}]),
      selected_subscription_keys: MapSet.new([{:analog_input, 1, :present_value}])
    }

    c = %{"key" => "c", "code" => "KeyC", "shift" => false}

    assert Shortcuts.device_action(c, assigns) == :none
  end

  test "blocking_modal_open? detects write and other modal assigns" do
    refute Shortcuts.blocking_modal_open?(%{})
    refute Shortcuts.blocking_modal_open?(%{write_property_modal: nil, show_shortcuts: false})

    assert Shortcuts.blocking_modal_open?(%{write_property_modal: %{property: :present_value}})
    assert Shortcuts.blocking_modal_open?(%{write_modal: %{type: :analog_value}})
    assert Shortcuts.blocking_modal_open?(%{reset_priority_modal: %{mode: :confirm, priority: 8}})
    assert Shortcuts.blocking_modal_open?(%{show_shortcuts: true})
    assert Shortcuts.blocking_modal_open?(%{log_viewer_open: true})
    assert Shortcuts.blocking_modal_open?(%{device_service_modal: %{type: :dcc}})
  end

  test "ignore_global_shortcut? blocks non-Escape keys when a modal is open" do
    open = %{write_property_modal: %{property: :present_value}}
    closed = %{write_property_modal: nil}

    digit = %{"key" => "1", "code" => "Digit1", "shift" => false}
    letter = %{"key" => "r", "code" => "KeyR", "shift" => false}
    escape = %{"key" => "Escape", "code" => "Escape", "shift" => false}

    assert Shortcuts.ignore_global_shortcut?(digit, open)
    assert Shortcuts.ignore_global_shortcut?(letter, open)
    refute Shortcuts.ignore_global_shortcut?(escape, open)

    refute Shortcuts.ignore_global_shortcut?(digit, closed)
    refute Shortcuts.ignore_global_shortcut?(letter, closed)
    refute Shortcuts.ignore_global_shortcut?(escape, closed)
  end

  test "escape_key? matches Escape only" do
    assert Shortcuts.escape_key?(%{"key" => "Escape"})
    assert Shortcuts.escape_key?("Escape")
    refute Shortcuts.escape_key?(%{"key" => "1"})
    refute Shortcuts.escape_key?("r")
  end

  test "escape_close_action prefers write modals over shortcuts help" do
    assert Shortcuts.escape_close_action(%{
             write_property_modal: %{property: :present_value},
             show_shortcuts: true
           }) == {:event, "close_write_property_modal"}

    assert Shortcuts.escape_close_action(%{write_modal: %{type: :analog_value}}) ==
             {:event, "close_write_modal"}

    assert Shortcuts.escape_close_action(%{log_viewer_open: true}) == {:event, "close_log_viewer"}

    assert Shortcuts.escape_close_action(%{show_shortcuts: true}) == :close_shortcuts
    assert Shortcuts.escape_close_action(%{}) == :none
  end

  test "apply_escape_close dispatches LiveView close events" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:write_property_modal, %{property: :present_value})
      |> Phoenix.Component.assign(:show_shortcuts, false)

    assert {:noreply, closed} =
             Shortcuts.apply_escape_close(socket, fn "close_write_property_modal", sock ->
               {:noreply, Phoenix.Component.assign(sock, :write_property_modal, nil)}
             end)

    assert closed.assigns.write_property_modal == nil
  end

  test "apply_escape_close closes shortcuts help without dispatch" do
    socket = Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, :show_shortcuts, true)

    assert {:noreply, closed} =
             Shortcuts.apply_escape_close(socket, fn _event, _sock ->
               flunk("should not dispatch for shortcuts help")
             end)

    assert closed.assigns.show_shortcuts == false
  end
end
