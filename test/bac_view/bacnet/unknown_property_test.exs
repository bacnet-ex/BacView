defmodule BacView.BACnet.Protocol.UnknownPropertyTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.{BACnetDate, BACnetTime}
  alias BacView.BACnet.Protocol.UnknownProperty

  test "formats primitive encodings without type prefix" do
    encoding = %Encoding{
      encoding: :primitive,
      type: :unsigned_integer,
      value: 41_160,
      extras: []
    }

    presented = UnknownProperty.present(encoding)
    assert presented.formatted == "41160"
    assert presented.display_value == 41_160
    assert presented.type == "UNSIGNED INTEGER"
  end

  test "detects binary values inside Encoding wrappers" do
    encoding = %Encoding{
      encoding: :primitive,
      type: :character_string,
      value: "x",
      extras: []
    }

    presented = UnknownProperty.present(encoding)
    assert presented.string_value?
    assert presented.raw_binary == "x"
    assert presented.formatted == "x"
    assert presented.type == "CHARACTER STRING"
    refute presented.hex_toggle?
  end

  test "treats unknown Encoding lists as proprietary hex dumps" do
    encoding_list = [
      %Encoding{
        encoding: :primitive,
        type: :date,
        value: %BACnetDate{year: 2026, month: 1, day: 15, weekday: 3},
        extras: []
      },
      %Encoding{
        encoding: :primitive,
        type: :time,
        value: %BACnetTime{hour: 12, minute: 30, second: 0, hundredth: 0},
        extras: []
      }
    ]

    presented = UnknownProperty.present(encoding_list)
    assert presented.type == "PROPRIETARY"
    assert presented.string_value?
    refute presented.hex_toggle?
    assert presented.formatted =~ ":"
    refute presented.formatted =~ "REAL:"
    refute presented.formatted =~ "DATE:"
  end

  test "offers hex toggle only for non-printable binary values" do
    printable = %Encoding{
      encoding: :primitive,
      type: :character_string,
      value: "hello",
      extras: []
    }

    non_printable = %Encoding{
      encoding: :primitive,
      type: :character_string,
      value: "a\0b",
      extras: []
    }

    refute UnknownProperty.present(printable).hex_toggle?
    assert UnknownProperty.present(non_printable).hex_toggle?
  end
end
