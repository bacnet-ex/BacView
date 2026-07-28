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

  test "from_object prefers top-level status_flags" do
    top = %StatusFlags{in_alarm: true, fault: false, overridden: false, out_of_service: false}
    unknown = %StatusFlags{in_alarm: false, fault: true, overridden: false, out_of_service: false}

    assert StatusFlagsParser.from_object(%{
             status_flags: top,
             _unknown_properties: %{status_flags: unknown}
           }) == top
  end

  test "from_object falls back to _unknown_properties.status_flags" do
    flags = %StatusFlags{in_alarm: false, fault: true, overridden: false, out_of_service: false}

    assert StatusFlagsParser.from_object(%{
             status_flags: nil,
             _unknown_properties: %{status_flags: flags}
           }) == flags
  end

  test "from_object normalizes Encoding under _unknown_properties" do
    encoding = %Encoding{
      encoding: :primitive,
      type: :bitstring,
      value: {false, true, false, false},
      extras: []
    }

    assert %StatusFlags{in_alarm: false, fault: true, overridden: false, out_of_service: false} =
             StatusFlagsParser.from_object(%{_unknown_properties: %{status_flags: encoding}})
  end

  test "from_object returns nil when neither source is present" do
    assert StatusFlagsParser.from_object(%{name: "AI-1"}) == nil
    assert StatusFlagsParser.from_object(nil) == nil
  end
end
