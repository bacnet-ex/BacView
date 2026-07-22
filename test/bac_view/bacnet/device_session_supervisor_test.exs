defmodule BacView.BACnet.DeviceSessionSupervisorTest do
  # stop_all/0 touches the global DeviceSession supervisor — keep serial.
  use ExUnit.Case, async: false

  alias BacView.BACnet.DeviceSessionSupervisor

  test "session infrastructure is available in the test app" do
    assert DeviceSessionSupervisor.available?()
  end

  test "session_pid returns nil for unknown devices without crashing" do
    assert DeviceSessionSupervisor.session_pid(999_999) == nil
  end

  test "stop_all terminates running sessions" do
    device_id = 9_001_043
    assert {:ok, pid} = DeviceSessionSupervisor.ensure_session(device_id)
    assert Process.alive?(pid)

    assert DeviceSessionSupervisor.stop_all() == :ok

    refute Process.alive?(pid)
    assert DeviceSessionSupervisor.session_pid(device_id) == nil
  end
end
