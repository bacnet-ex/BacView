defmodule BacView.BACnet.ForeignRegistrationTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.ForeignRegistration

  test "route returns :bbmd when foreign device is active" do
    state = %{
      fd_pid: self(),
      bbmd: {{192, 168, 1, 1}, 47_808}
    }

    settings = %{bbmd_host: "192.168.1.1", bbmd_port: 47_808, bbmd_ttl: 600}

    assert ForeignRegistration.route(state, settings) == :bbmd
  end

  test "route returns :bbmd_required when host configured but not registered" do
    state = %{fd_pid: nil, bbmd: nil}
    settings = %{bbmd_host: "192.168.1.1", bbmd_port: 47_808, bbmd_ttl: 600}

    assert ForeignRegistration.route(state, settings) == :bbmd_required
  end

  test "route returns :local without bbmd configuration" do
    state = %{fd_pid: nil, bbmd: nil}
    settings = %{bbmd_host: nil, bbmd_port: 47_808, bbmd_ttl: 600}

    assert ForeignRegistration.route(state, settings) == :local
  end
end
