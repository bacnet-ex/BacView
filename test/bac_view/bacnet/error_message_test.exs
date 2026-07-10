defmodule BacView.BACnet.Protocol.ErrorMessageTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.APDU
  alias BacView.BACnet.Protocol.ErrorMessage

  test "formats BACnet error APDU with user-friendly COV message" do
    error = %APDU.Error{
      invoke_id: 1,
      service: :subscribe_cov_property,
      class: :services,
      code: :optional_functionality_not_supported,
      payload: []
    }

    message = ErrorMessage.for_action(:cov_subscribe, {:bacnet_error, error})

    assert message =~ "COV-Abonnement fehlgeschlagen"
    assert message =~ "unterstützt diese Funktion nicht"
    refute message =~ "Error"
    refute message =~ "invoke_id"
  end

  test "formats reject reasons for users" do
    reject = %APDU.Reject{invoke_id: 2, reason: :reject_unrecognized_service}

    assert ErrorMessage.format_reason({:bacnet_reject, reject}) =~
             "unterstützt diesen Dienst nicht"
  end

  test "detail includes full error struct for developers" do
    error = %APDU.Error{
      invoke_id: 3,
      service: :subscribe_cov,
      class: :services,
      code: :cov_subscription_failed,
      payload: []
    }

    detail = ErrorMessage.detail({:bacnet_error, error})

    assert detail =~ "invoke_id: 3"
    assert detail =~ "cov_subscription_failed"
  end

  test "formats common atoms" do
    assert ErrorMessage.format_reason(:device_not_found) =~ "Gerät nicht gefunden"
    assert ErrorMessage.format_reason(:timeout) =~ "Zeitüberschreitung"
    assert ErrorMessage.format_reason(:stack_not_started) =~ "nicht gestartet"
  end

  test "formats stack restart action" do
    message = ErrorMessage.for_action(:stack_restart, :stack_not_started)

    assert message =~ "Stack-Neustart fehlgeschlagen"
    assert message =~ "nicht gestartet"
  end

  test "formats supervisor shutdown errors for serial ports" do
    assert ErrorMessage.format_reason({:shutdown, :eacces}) =~ "verweigert"
    assert ErrorMessage.format_reason(:enoent) =~ "nicht gefunden"
  end

  test "formats nested supervisor child startup failures" do
    reason =
      {{:shutdown, {:failed_to_start_child, BACnet.Stack.Transport.MstpTransport, :eacces}},
       {:child, :undefined, BacView.BACnet.Stack.Runtime, :start_link, :temporary, false,
        :infinity, :supervisor, [BacView.BACnet.Stack.Runtime]}}

    assert ErrorMessage.format_reason(reason) =~ "verweigert"
  end

  test "formats BACnet/IP port bind failures with explicit reason" do
    reason =
      {{:shutdown, {:failed_to_start_child, BACnet.Stack.Transport.IPv4Transport, :eaddrinuse}},
       {:child, :undefined, BacView.BACnet.Stack.Runtime, :start_link, :temporary, false,
        :infinity, :supervisor, [BacView.BACnet.Stack.Runtime]}}

    message = ErrorMessage.format_reason(reason)

    assert message =~ "eaddrinuse"
    assert message =~ "UDP-Port"
    assert message =~ "BACnet-Anwendung"
  end

  test "formats missing serial ports startup failures" do
    reason =
      {:no_serial_ports,
       {:child, :undefined, BacView.BACnet.Stack.Runtime, :start_link, :temporary, false,
        :infinity, :supervisor, [BacView.BACnet.Stack.Runtime]}}

    assert ErrorMessage.format_reason(reason) =~ "seriellen Ports"
  end

  test "formats unknown atoms with readable reason code" do
    assert ErrorMessage.format_reason(:einval) =~ "einval"
  end
end
