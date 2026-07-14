defmodule BacView.TextTest do
  use ExUnit.Case, async: true

  alias BacView.Text

  test "sanitize_utf8 keeps valid UTF-8" do
    assert Text.sanitize_utf8("Cov Increment: —") == "Cov Increment: —"
  end

  test "sanitize_utf8 converts Latin-1 CharacterString bytes to UTF-8" do
    latin1 = <<"K\xE4ltemaschine 1">>

    refute String.valid?(latin1)

    sanitized = Text.sanitize_utf8(latin1)

    assert sanitized == "Kältemaschine 1"
    assert String.valid?(sanitized)
    assert Jason.encode!(sanitized)
  end

  test "sanitize_utf8 fixes invalid UTF-8 bytes for JSON encoding" do
    invalid = <<"Cov Increment: ", 226, 128, 148, ", text ", 192, " rest">>

    refute String.valid?(invalid)

    sanitized = Text.sanitize_utf8(invalid)

    assert String.valid?(sanitized)
    assert Jason.encode!(sanitized)
    assert sanitized =~ "Cov Increment:"
  end

  test "sanitize_property_row sanitizes nested display strings" do
    row = %{
      property: :active_cov_subscriptions,
      property_name: "active cov",
      value: %{cov_increment: <<"—", 192>>},
      value_formatted: <<"Cov Increment: ", 192>>,
      value_display: %{
        kind: :struct,
        formatted: <<"Cov Increment: ", 192>>,
        fields: [
          %{
            key: :cov_increment,
            label: "Cov Increment",
            kind: :scalar,
            value: <<"—", 192>>,
            formatted: <<"—", 192>>,
            fields: []
          }
        ],
        items: []
      }
    }

    sanitized = Text.sanitize_property_row(row)

    assert String.valid?(sanitized.value_formatted)
    assert Jason.encode!(sanitized.value_display.formatted)
    assert Jason.encode!(hd(sanitized.value_display.fields).formatted)
  end

  test "sanitize_property_row keeps recipient address hex display JSON-safe" do
    row = %{
      property: :active_cov_subscriptions,
      property_name: "active cov subscriptions",
      value: [
        %BACnet.Protocol.CovSubscription{
          recipient: %BACnet.Protocol.Recipient{
            type: :address,
            device: nil,
            address: %BACnet.Protocol.RecipientAddress{
              network: 0,
              address: <<192, 168, 1, 73, 186, 192>>
            }
          },
          recipient_process: 1,
          monitored_object_property: %BACnet.Protocol.ObjectPropertyRef{
            object_identifier: %BACnet.Protocol.ObjectIdentifier{
              type: :analog_input,
              instance: 1
            },
            property_identifier: :present_value,
            property_array_index: nil
          },
          issue_confirmed_notifications: false,
          time_remaining: 60,
          cov_increment: 1.0
        }
      ],
      value_formatted: "0/192.168.1.73:47808",
      value_display: %{
        kind: :array,
        formatted: "address: Network: 0, Address: 192.168.1.73:47808",
        fields: [],
        items: [
          %{
            key: 1,
            label: "[1]",
            kind: :array_item,
            formatted: "address: Network: 0, Address: 192.168.1.73:47808",
            fields: [
              %{
                key: :recipient,
                label: "Recipient",
                kind: :struct,
                formatted: "address: Network: 0, Address: 192.168.1.73:47808",
                fields: [
                  %{
                    key: :address,
                    label: "Address",
                    kind: :struct,
                    formatted: "Network: 0, Address: 192.168.1.73:47808",
                    fields: [
                      %{
                        key: :address,
                        label: "Address",
                        kind: :scalar,
                        formatted: "192.168.1.73:47808",
                        fields: []
                      }
                    ],
                    items: []
                  }
                ],
                items: []
              }
            ],
            items: []
          }
        ]
      }
    }

    sanitized = Text.sanitize_property_row(row)

    assert Jason.encode!(sanitized.value_display)
    assert sanitized.value_display.items |> hd() |> Map.get(:formatted) =~ "192.168.1.73:47808"
  end
end
