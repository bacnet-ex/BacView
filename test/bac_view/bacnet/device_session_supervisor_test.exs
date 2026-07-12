defmodule BacView.BACnet.DeviceSessionSupervisorTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.DeviceSessionSupervisor

  test "session infrastructure is available in the test app" do
    assert DeviceSessionSupervisor.available?()
  end

  test "session_pid returns nil for unknown devices without crashing" do
    assert DeviceSessionSupervisor.session_pid(999_999) == nil
  end
end
