defmodule BacView.BACnet.ClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.Test.SilenceLogger

  test "log_read_error writes a warning by default" do
    object = %ObjectIdentifier{type: :analog_input, instance: 1}
    destination = {{10, 0, 0, 5}, 47_808}

    log =
      SilenceLogger.with_logging(
        fn ->
          capture_log(fn ->
            Client.log_read_error(
              :read_property,
              destination,
              object,
              :present_value,
              :timeout
            )
          end)
        end,
        unsilence: [Client]
      )

    assert log =~ "BACnet read_property failed"
    assert log =~ "analog_input:1"
    assert log =~ "present_value"
    assert log =~ "10.0.0.5:47808"
    assert log =~ "timeout"
    assert log =~ "[warning]" or log =~ "warning"
  end

  test "log_request_error is the shared outgoing/read helper" do
    object = %ObjectIdentifier{type: :analog_value, instance: 9}
    destination = {{10, 0, 0, 8}, 47_808}

    log =
      SilenceLogger.with_logging(
        fn ->
          capture_log(fn ->
            Client.log_request_error(
              :write_property,
              destination,
              object,
              :event_parameters,
              :timeout,
              device_id: 42
            )
          end)
        end,
        unsilence: [Client]
      )

    assert log =~ "BACnet write_property failed"
    assert log =~ "device 42"
    assert log =~ "analog_value:9"
    assert log =~ "event_parameters"
    assert log =~ "10.0.0.8:47808"
  end

  test "log_request_error formats casting exceptions for operators" do
    exception = %FunctionClauseError{
      module: BACnet.Protocol.ApplicationTags.Encoding,
      function: :to_encoding,
      arity: 1
    }

    message =
      Client.request_error_message(
        :write_property,
        nil,
        nil,
        :event_parameters,
        {:exception_during_casting, exception, []}
      )

    assert message =~ "write_property failed"
    assert message =~ "Lokale BACnet-Kodierung"
    assert message =~ "to_encoding"
  end

  test "log_read_error can use debug level for expected fallbacks" do
    log =
      SilenceLogger.with_logging(
        fn ->
          Logger.put_module_level(Client, :debug)

          capture_log([level: :debug], fn ->
            Client.log_read_error(:read_object, nil, nil, nil, :timeout, level: :debug)
          end)
        end,
        unsilence: [Client]
      )

    assert log =~ "BACnet read_object failed"
    refute log =~ "[warning]"
  end

  test "read_error_message formats destination, object, and property" do
    object = %ObjectIdentifier{type: :analog_input, instance: 1}
    destination = {{10, 0, 0, 5}, 47_808}

    message =
      Client.read_error_message(
        :read_property,
        destination,
        object,
        :present_value,
        :timeout
      )

    assert message =~ "BACnet read_property failed"
    assert message =~ "analog_input:1"
    assert message =~ "present_value"
    assert message =~ "10.0.0.5:47808"
  end
end
