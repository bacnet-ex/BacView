defmodule BacView.BACnet.Protocol.StatusFlagsParserTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.StatusFlags
  alias BacView.BACnet.Protocol.StatusFlagsParser

  test "normalizes StatusFlags struct" do
    flags = %StatusFlags{in_alarm: false, fault: false, overridden: false, out_of_service: true}
    assert StatusFlagsParser.normalize(flags) == flags
  end

  test "normalizes bitstring tuple tag" do
    assert %StatusFlags{in_alarm: false, fault: false, overridden: false, out_of_service: true} =
             StatusFlagsParser.normalize({:bitstring, {false, false, false, true}})
  end

  test "normalizes bare four-tuple" do
    assert %StatusFlags{in_alarm: true, fault: false, overridden: false, out_of_service: false} =
             StatusFlagsParser.normalize({true, false, false, false})
  end

  test "normalizes Encoding wrapper" do
    encoding = %Encoding{
      encoding: :primitive,
      type: :bitstring,
      value: {false, false, false, true},
      extras: []
    }

    assert %StatusFlags{in_alarm: false, fault: false, overridden: false, out_of_service: true} =
             StatusFlagsParser.normalize(encoding)
  end
end
