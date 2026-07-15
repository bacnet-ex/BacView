defmodule BacView.BACnet.ClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.Test.SilenceLogger

  test "log_read_error writes a warning to the console" do
    object = %ObjectIdentifier{type: :analog_input, instance: 1}
    destination = {{10, 0, 0, 5}, 47_808}

    log =
      capture_log(fn ->
        SilenceLogger.with_logging(fn ->
          Client.log_read_error(
            :read_property,
            destination,
            object,
            :present_value,
            :timeout
          )
        end)
      end)

    assert log =~ "BACnet read_property failed"
    assert log =~ "analog_input:1"
    assert log =~ "present_value"
    assert log =~ "10.0.0.5:47808"
    assert log =~ "timeout"
  end

  test "log_read_error can be suppressed via opts" do
    log =
      capture_log(fn ->
        SilenceLogger.with_logging(fn ->
          Client.log_read_error(:read_object, nil, nil, nil, :timeout, log_read_error: false)
        end)
      end)

    assert log == ""
  end
end
