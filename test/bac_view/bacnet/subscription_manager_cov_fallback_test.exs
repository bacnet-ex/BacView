defmodule BacView.BACnet.SubscriptionManagerCovFallbackTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.APDU
  alias BacView.BACnet.SubscriptionManager

  test "cov_property_fallback? matches unsupported service errors" do
    assert SubscriptionManager.cov_property_fallback?(
             {:bacnet_error,
              %APDU.Error{
                invoke_id: 1,
                service: :subscribe_cov_property,
                class: :services,
                code: :optional_functionality_not_supported,
                payload: []
              }}
           )

    assert SubscriptionManager.cov_property_fallback?(
             {:bacnet_reject, %APDU.Reject{invoke_id: 1, reason: :reject_unrecognized_service}}
           )

    assert SubscriptionManager.cov_property_fallback?(
             {:bacnet_reject, %APDU.Reject{invoke_id: 1, reason: :unrecognized_service}}
           )
  end

  test "cov_property_fallback? ignores operational errors" do
    refute SubscriptionManager.cov_property_fallback?(
             {:bacnet_error,
              %APDU.Error{
                invoke_id: 1,
                service: :subscribe_cov_property,
                class: :object,
                code: :unknown_object,
                payload: []
              }}
           )

    refute SubscriptionManager.cov_property_fallback?({:error, :timeout})
    refute SubscriptionManager.cov_property_fallback?(:device_not_found)
  end
end
