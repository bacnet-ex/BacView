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
end
