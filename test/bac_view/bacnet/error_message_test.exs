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

  test "formats BACnet property validation errors" do
    assert ErrorMessage.format_reason({:invalid_property_value, {:network_type, 68}}) =~
             "ungültig"

    assert ErrorMessage.format_reason({:missing_optional_property, :bacnet_ip_mode}) =~
             "optionale"

    assert ErrorMessage.format_reason({:value_failed_property_validation, :present_value}) =~
             "present value"

    assert ErrorMessage.format_reason({:invalid_property_type, :present_value}) =~
             "present value"
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

  test "formats GenServer.call timeout exits" do
    reason = {:timeout, {GenServer, :call, [self(), :load, 120_000]}}

    assert ErrorMessage.format_reason(reason) =~ "Zeitüberschreitung"
    refute ErrorMessage.format_reason(reason) =~ "unerwarteter"
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

  test "formats property read fallback errors" do
    assert ErrorMessage.format_reason(:object_unavailable) =~ "Objekt"
    assert ErrorMessage.format_reason(:property_list_not_readable) =~ "Eigenschaftsliste"
    assert ErrorMessage.format_reason({:property_read_failed, :timeout}) =~ "Zeitüberschreitung"
  end

  test "formats bacstack exception_during_casting with function clause detail" do
    exception = %FunctionClauseError{
      module: BACnet.Protocol.ApplicationTags.Encoding,
      function: :to_encoding,
      arity: 1
    }

    reason = {:exception_during_casting, exception, []}
    message = ErrorMessage.format_reason(reason)
    action = ErrorMessage.for_action(:write_property, reason)

    assert message =~ "Lokale BACnet-Kodierung"
    assert message =~ "to_encoding"
    assert message =~ "ApplicationTags.Encoding"
    refute message =~ "unerwarteter Fehler"

    assert action =~ "Schreiben fehlgeschlagen"
    assert action =~ "Lokale BACnet-Kodierung"
  end

  test "formats exception_during_encoding and decoding" do
    exception = %RuntimeError{message: "boom"}

    assert ErrorMessage.format_reason({:exception_during_encoding, exception, []}) =~
             "BACnet-Kodierung fehlgeschlagen"

    assert ErrorMessage.format_reason({:exception_during_decoding, exception, []}) =~
             "BACnet-Dekodierung fehlgeschlagen"
  end

  test "formats missing encode/parse fun and invalid_params" do
    assert ErrorMessage.format_reason(
             {:missing_encode_fun, BACnet.Protocol.EventParameters.OutOfRange}
           ) =~
             "Encode-Funktion"

    assert ErrorMessage.format_reason({:missing_parse_fun, BACnet.Protocol.EventParameters}) =~
             "Parse-Funktion"

    assert ErrorMessage.format_reason(:invalid_params) =~ "Ungültige Parameter"
    assert ErrorMessage.format_reason(:unsupported_object_type) =~ "nicht unterstützt"
  end

  test "formats unknown tagged reasons with code and detail instead of bare generic" do
    message = ErrorMessage.format_reason({:some_new_stack_error, :event_parameters})

    assert message =~ "some new stack error"
    assert message =~ "event_parameters"
    refute message == "Ein unerwarteter Fehler ist aufgetreten."
  end

  test "formats IPv4 transport interface startup failures with interface name" do
    interface = ~S"\DEVICE\TCPIP_{8D7A9EC4-3DCD-4969-ACFB-5BF7E4115340}"

    reason =
      {{:shutdown,
        {:failed_to_start_child, BACnet.Stack.Transport.IPv4Transport,
         {%RuntimeError{
            message:
              "Unable to find ethernet interface (with broadcast flag) called " <> interface
          }, []}}},
       {:child, :undefined, BacView.BACnet.Stack.Runtime, :start_link, :temporary, false,
        :infinity, :supervisor, [BacView.BACnet.Stack.Runtime]}}

    message = ErrorMessage.format_reason(reason)

    assert message =~ "Netzwerkschnittstelle nicht gefunden"
    assert message =~ interface
    refute message =~ "unerwarteter Fehler"
  end

  test "formats stack restart action for missing IPv4 interface" do
    interface = "eth0"

    reason =
      {{:shutdown,
        {:failed_to_start_child, BACnet.Stack.Transport.IPv4Transport,
         {%RuntimeError{
            message:
              "Unable to find ethernet interface (with broadcast flag) called " <> interface
          }, []}}},
       {:child, :undefined, BacView.BACnet.Stack.Runtime, :start_link, :temporary, false,
        :infinity, :supervisor, [BacView.BACnet.Stack.Runtime]}}

    message = ErrorMessage.for_action(:stack_restart, reason)

    assert message =~ "Stack-Neustart fehlgeschlagen"
    assert message =~ interface
    refute message =~ "unerwarteter Fehler"
  end
end
