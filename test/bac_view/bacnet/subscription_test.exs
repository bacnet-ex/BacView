defmodule BacView.BACnet.SubscriptionTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Subscription

  test "needs_renewal when within 20% of expiry" do
    now = ~U[2026-01-01 12:00:00Z]
    expires = DateTime.add(now, 100, :second)

    sub = %{
      lifetime: 3600,
      expires_at: expires,
      subscribed_at: DateTime.add(now, -3500, :second)
    }

    assert Subscription.needs_renewal?(sub, now)
  end

  test "does not renew when lifetime is zero" do
    sub = %{lifetime: 0, expires_at: nil, subscribed_at: DateTime.utc_now()}
    refute Subscription.needs_renewal?(sub, DateTime.utc_now())
  end

  test "build creates subscription record" do
    oid = %ObjectIdentifier{type: :analog_input, instance: 1}

    sub =
      Subscription.build(42, {127, 0, 0, 1, 47808}, oid, :present_value,
        lifetime: 3600,
        confirmed: false,
        process_id: 123
      )

    assert sub.device_id == 42
    assert sub.property == :present_value
    assert sub.process_id == 123
    assert Map.has_key?(sub, :time_remaining)
    assert Map.has_key?(sub, :last_cov_at)
  end

  test "build map supports cov notification field updates" do
    oid = %ObjectIdentifier{type: :analog_input, instance: 1}

    sub =
      Subscription.build(1, {127, 0, 0, 1, 47_808}, oid, :present_value,
        lifetime: 3600,
        confirmed: false,
        process_id: 1
      )

    updated =
      Map.merge(sub, %{
        last_cov_at: DateTime.utc_now(),
        last_value: 42.0,
        last_value_formatted: "42.0",
        time_remaining: 1800
      })

    assert updated.last_value == 42.0
    assert updated.time_remaining == 1800
  end
end
