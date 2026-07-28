defmodule BacView.BACnet.Protocol.UnknownPropertyTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.{BACnetDate, BACnetTime}
  alias BacView.BACnet.Protocol.PropertyFormatter
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
    assert presented.primitive_editable?
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
    assert presented.primitive_editable?
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
    refute presented.primitive_editable?
    assert presented.formatted =~ ":"
    refute presented.formatted =~ "REAL:"
    refute presented.formatted =~ "DATE:"
  end

  test "marks date/time and object identifiers as not primitive-editable" do
    date_encoding = %Encoding{
      encoding: :primitive,
      type: :date,
      value: %BACnetDate{year: 2026, month: 1, day: 15, weekday: 3},
      extras: []
    }

    refute UnknownProperty.present(date_encoding).primitive_editable?
  end

  test "never offers hex toggle for character-string values" do
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
    refute UnknownProperty.present(non_printable).hex_toggle?
  end

  test "always offers hex toggle for typed octet strings, even when printable" do
    printable_octet = %Encoding{
      encoding: :primitive,
      type: :octet_string,
      value: "ABCD",
      extras: []
    }

    non_printable_octet = %Encoding{
      encoding: :primitive,
      type: :octet_string,
      value: <<1, 2, 0, 3>>,
      extras: []
    }

    printable = UnknownProperty.present(printable_octet)
    non_printable = UnknownProperty.present(non_printable_octet)

    # Printable: text vs hex — toggle is useful
    assert printable.hex_toggle?
    assert printable.formatted == "ABCD"
    assert PropertyFormatter.format_binary_hex(printable.raw_binary) == "41:42:43:44"

    # Already defaulting to hex — toggle would no-op, so hide it
    refute non_printable.hex_toggle?
    assert non_printable.formatted == "01:02:00:03"
  end
end
