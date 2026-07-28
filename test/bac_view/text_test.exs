defmodule BacView.TextTest do
  use ExUnit.Case, async: true

  alias BacView.Text

  test "sanitize_utf8 keeps valid UTF-8" do
    assert Text.sanitize_utf8("Cov Increment: -") == "Cov Increment: -"
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
      value: %{cov_increment: <<"-", 192>>},
      value_formatted: <<"Cov Increment: ", 192>>,
      value_display: %{
        kind: :struct,
        formatted: <<"Cov Increment: ", 192>>,
        fields: [
          %{
            key: :cov_increment,
            label: "Cov Increment",
            kind: :scalar,
            value: <<"-", 192>>,
            formatted: <<"-", 192>>,
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

  test "sanitize_property_row preserves opaque MAC octets on value and raw_binary" do
    # NetworkPort mac_address sample that is not valid UTF-8 (high bytes).
    mac = <<10, 130, 3, 51, 186, 192>>
    formatted = "0A:82:03:33:BA:C0"

    row = %{
      property: :mac_address,
      property_name: "mac address",
      bac_type: :octet_string,
      type: "OCTET STRING",
      value: mac,
      value_formatted: formatted,
      value_display: %{kind: :scalar, formatted: formatted, fields: [], items: []},
      string_value?: true,
      hex_toggle?: true,
      raw_binary: mac
    }

    sanitized = Text.sanitize_property_row(row)

    assert sanitized.raw_binary == mac
    assert sanitized.value == mac
    assert byte_size(sanitized.raw_binary) == 6
    assert sanitized.value_formatted == formatted
    # Must not Latin-1-expand into 9-byte UTF-8 (0A:C2:82:…:C3:80).
    refute sanitized.raw_binary == <<10, 194, 130, 3, 51, 194, 186, 195, 128>>
  end

  test "sanitize_property_row preserves nested RecipientAddress MAC field values" do
    mac = <<192, 168, 1, 73, 186, 192>>

    row = %{
      property: :active_cov_subscriptions,
      property_name: "active cov",
      value: nil,
      value_formatted: "ok",
      value_display: %{
        kind: :struct,
        formatted: "Network: 0, Address: 192.168.1.73:47808",
        fields: [
          %{
            key: :address,
            label: "Address",
            kind: :scalar,
            value: mac,
            formatted: "192.168.1.73:47808",
            fields: []
          }
        ],
        items: []
      }
    }

    sanitized = Text.sanitize_property_row(row)
    field = hd(sanitized.value_display.fields)

    assert field.value == mac
    assert byte_size(field.value) == 6
  end

  test "sanitize_property_row still Latin-1-repairs character-string values" do
    latin1 = <<"K\xE4lte">>

    row = %{
      property: :description,
      property_name: "description",
      bac_type: :string,
      type: "CHARACTER STRING",
      value: latin1,
      value_formatted: "placeholder",
      value_display: %{kind: :scalar, formatted: "placeholder", fields: [], items: []},
      string_value?: true,
      hex_toggle?: false,
      raw_binary: latin1
    }

    sanitized = Text.sanitize_property_row(row)

    assert sanitized.value == "Kälte"
    # raw_binary stays original for hex toggle re-encoding
    assert sanitized.raw_binary == latin1
  end

  test "opaque_binary? detects non-text octets" do
    assert Text.opaque_binary?(<<10, 130, 3, 51, 186, 192>>)
    assert Text.opaque_binary?("a\0b")
    refute Text.opaque_binary?("ABCD")
  end
end
