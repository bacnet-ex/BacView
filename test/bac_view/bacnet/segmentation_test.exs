defmodule BacView.BACnet.SegmentationTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.APDU
  alias BacView.BACnet.Segmentation

  test "detects direct segmentation and buffer overflow errors" do
    assert Segmentation.fallback_error?({:error, :segmentation_not_supported})
    assert Segmentation.fallback_error?({:error, :buffer_overflow})
    assert Segmentation.fallback_error?({:error, {:segmentation_not_supported, :oid}})
    assert Segmentation.fallback_error?({:error, {:buffer_overflow, :oid}})
    refute Segmentation.fallback_error?({:error, :timeout})
  end

  test "detects abort reasons for segmentation and buffer overflow" do
    segmentation_abort = %APDU.Abort{
      sent_by_server: true,
      invoke_id: 1,
      reason: :segmentation_not_supported
    }

    buffer_abort = %APDU.Abort{sent_by_server: true, invoke_id: 2, reason: :buffer_overflow}
    timeout_abort = %APDU.Abort{sent_by_server: true, invoke_id: 3, reason: :tsm_timeout}

    assert Segmentation.fallback_error?({:error, {:bacnet_abort, segmentation_abort}})
    assert Segmentation.fallback_error?({:error, {:bacnet_abort, buffer_abort}})

    assert Segmentation.fallback_error?(
             {:error, {{:bacnet_abort, %{segmentation_abort | reason: 4}}, :oid}}
           )

    assert Segmentation.fallback_error?(
             {:error, {{:bacnet_abort, %{buffer_abort | reason: 1}}, :oid}}
           )

    refute Segmentation.fallback_error?({:error, {:bacnet_abort, timeout_abort}})
  end

  test "detects reject reasons for buffer overflow" do
    buffer_reject = %APDU.Reject{invoke_id: 1, reason: :buffer_overflow}
    service_reject = %APDU.Reject{invoke_id: 2, reason: :reject_unrecognized_service}

    assert Segmentation.fallback_error?({:error, {:bacnet_reject, buffer_reject}})

    assert Segmentation.fallback_error?(
             {:error, {{:bacnet_reject, %{buffer_reject | reason: 1}}, :oid}}
           )

    refute Segmentation.fallback_error?({:error, {:bacnet_reject, service_reject}})
  end

  test "rpm_fallback_error? includes unrecognized service rejects for RPM fallback" do
    service_reject = %APDU.Reject{invoke_id: 2, reason: :reject_unrecognized_service}
    atom_reject = %APDU.Reject{invoke_id: 3, reason: :unrecognized_service}
    numeric_reject = %APDU.Reject{invoke_id: 4, reason: 9}

    assert Segmentation.rpm_fallback_error?({:error, {:bacnet_reject, service_reject}})
    assert Segmentation.rpm_fallback_error?({:error, {:bacnet_reject, atom_reject}})
    assert Segmentation.rpm_fallback_error?({:error, {:bacnet_reject, numeric_reject}})

    assert Segmentation.rpm_fallback_error?(
             {:error, {{:bacnet_reject, %{service_reject | reason: :unrecognized_service}}, :oid}}
           )

    refute Segmentation.rpm_fallback_error?({:error, :timeout})
  end

  test "array_fallback_error? includes segmentation and property_not_readable" do
    assert Segmentation.array_fallback_error?({:error, :segmentation_not_supported})
    assert Segmentation.array_fallback_error?({:error, :buffer_overflow})
    assert Segmentation.array_fallback_error?({:error, :property_not_readable})
    assert Segmentation.array_fallback_error?(:property_not_readable)
    assert Segmentation.array_fallback_error?({:error, {:property_not_readable, :oid}})
  end

  test "array_fallback_error? excludes unknown_property and timeout" do
    refute Segmentation.array_fallback_error?({:error, :unknown_property})
    refute Segmentation.array_fallback_error?({:error, :timeout})
    refute Segmentation.array_fallback_error?(:timeout)
  end
end
