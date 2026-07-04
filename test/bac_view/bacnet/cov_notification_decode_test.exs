defmodule BacView.BACnet.CovNotificationDecodeTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.Services.UnconfirmedCovNotification
  alias BACnet.Protocol.{BACnetDate, BACnetTime}

  test "bacstack decodes COV notifications with unspecified BACnetDateTime values" do
    req = %UnconfirmedServiceRequest{
      service: :unconfirmed_cov_notification,
      parameters: [
        {:tagged, {0, <<2, 122, 192, 0>>, 4}},
        {:tagged, {1, <<2, 1, 192, 13>>, 4}},
        {:tagged, {2, <<1, 64, 0, 189>>, 4}},
        {:tagged, {3, <<14, 16>>, 2}},
        {:constructed,
         {4,
          [
            {:tagged, {0, <<115>>, 1}},
            {:constructed,
             {2,
              [
                date: %BACnetDate{
                  year: :unspecified,
                  month: :unspecified,
                  day: :unspecified,
                  weekday: :unspecified
                },
                time: %BACnetTime{
                  hour: :unspecified,
                  minute: :unspecified,
                  second: :unspecified,
                  hundredth: :unspecified
                }
              ], 0}},
            {:tagged, {0, <<111>>, 1}},
            {:constructed, {2, {:bitstring, {true, false, false, true}}, 0}}
          ], 0}}
      ]
    }

    assert {:ok, %UnconfirmedCovNotification{} = notif} =
             UnconfirmedServiceRequest.to_service(req)

    assert length(notif.property_values) == 2

    assert Enum.any?(notif.property_values, fn prop ->
             match?(
               [
                 %Encoding{type: :date},
                 %Encoding{type: :time}
               ],
               prop.property_value
             )
           end)
  end
end
