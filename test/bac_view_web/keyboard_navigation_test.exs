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
      selected_subscription_keys: MapSet.new([{:analog_input, 1, :present_value}])
    }

    c = %{"key" => "c", "code" => "KeyC", "shift" => false}
    shift_c = %{"key" => "C", "code" => "KeyC", "shift" => true}
    u = %{"key" => "u", "code" => "KeyU", "shift" => false}
    e = %{"key" => "e", "code" => "KeyE", "shift" => false}

    assert Shortcuts.device_action(c, base) == {:event, "subscribe_selected_cov"}
    assert Shortcuts.device_action(u, base) == {:event, "unsubscribe_selected_cov"}
    assert Shortcuts.device_action(shift_c, base) == {:event, "subscribe_all_pv"}

    cov = %{base | tab: "subscriptions"}
    assert Shortcuts.device_action(c, cov) == {:event, "resubscribe_selected_subscriptions"}
    assert Shortcuts.device_action(u, cov) == {:event, "unsubscribe_selected_subscriptions"}

    alarms = %{base | tab: "alarms", nc_enrolled_count: 1}
    assert Shortcuts.device_action(c, alarms) == {:event, "subscribe_notification_classes"}
    assert Shortcuts.device_action(u, alarms) == {:event, "unsubscribe_notification_classes"}

    events = %{base | tab: "alarms", alarm_view: "event_information"}
    assert Shortcuts.device_action(e, events) == {:event, "refresh_alarms"}
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
end
