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

  test "needs_renewal when subscription already expired" do
    now = ~U[2026-01-01 12:00:00Z]
    expires = DateTime.add(now, -10, :second)

    sub = %{
      lifetime: 3600,
      expires_at: expires,
      subscribed_at: DateTime.add(now, -3610, :second)
    }

    assert Subscription.needs_renewal?(sub, now)
  end

  test "needs_renewal when expires_at indicates expiry" do
    now = ~U[2026-01-01 12:00:00Z]

    sub = %{
      lifetime: 3600,
      expires_at: now,
      time_remaining: 0
    }

    assert Subscription.needs_renewal?(sub, now)
  end

  test "needs_renewal uses expires_at instead of stale time_remaining" do
    now = ~U[2026-01-01 12:00:00Z]

    sub = %{
      lifetime: 120,
      expires_at: DateTime.add(now, 20, :second),
      time_remaining: 90
    }

    assert Subscription.needs_renewal?(sub, now)
  end

  test "does not renew when lifetime is zero" do
    sub = %{lifetime: 0, expires_at: nil, subscribed_at: DateTime.utc_now()}
    refute Subscription.needs_renewal?(sub, DateTime.utc_now())
  end

  test "renew_check_interval_ms scales down for short lifetimes" do
    assert Subscription.renew_check_interval_ms(3600) == 45_000
    assert Subscription.renew_check_interval_ms(150) == 10_000
    assert Subscription.renew_check_interval_ms(60) == 10_000
  end

  test "effective_remaining is derived from expires_at" do
    now = ~U[2026-01-01 12:00:00Z]

    sub = %{
      expires_at: DateTime.add(now, 20, :second),
      time_remaining: 90
    }

    assert Subscription.effective_remaining(sub, now) == 20
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
    assert sub.cov_increment == nil
    assert sub.subscribe_service == :subscribe_cov_property
    assert Map.has_key?(sub, :time_remaining)
    assert Map.has_key?(sub, :last_cov_at)
  end

  test "build stores subscribe_service when fallback was used" do
    oid = %ObjectIdentifier{type: :analog_input, instance: 1}

    sub =
      Subscription.build(42, {127, 0, 0, 1, 47_808}, oid, :present_value,
        lifetime: 3600,
        confirmed: false,
        process_id: 123,
        subscribe_service: :subscribe_cov
      )

    assert sub.subscribe_service == :subscribe_cov
  end

  test "build stores cov_increment when provided" do
    oid = %ObjectIdentifier{type: :analog_input, instance: 1}

    sub =
      Subscription.build(42, {127, 0, 0, 1, 47_808}, oid, :present_value,
        lifetime: 3600,
        confirmed: false,
        process_id: 123,
        cov_increment: 0.1
      )

    assert sub.cov_increment == 0.1
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
