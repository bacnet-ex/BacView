defmodule BacView.BACnet.Protocol.BinaryPVTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.BinaryPV

  test "format_value uses inactive/active text when present" do
    object = %{type: :binary_value, inactive_text: "Closed", active_text: "Open"}

    assert BinaryPV.format_value(false, object) == "Closed"
    assert BinaryPV.format_value(true, object) == "Open"
    assert BinaryPV.format_value(0, object) == "Closed"
    assert BinaryPV.format_value(1, object) == "Open"
  end

  test "format_value falls back to false/true when texts missing" do
    object = %{type: :binary_input}

    assert BinaryPV.format_value(false, object) == "false"
    assert BinaryPV.format_value(true, object) == "true"
  end

  test "format_value falls back per missing side when only one text is present" do
    object = %{type: :binary_output, active_text: "Running"}

    assert BinaryPV.format_value(false, object) == "false"
    assert BinaryPV.format_value(true, object) == "Running"
  end

  test "format_value ignores blank state texts" do
    object = %{type: :binary_value, inactive_text: "  ", active_text: ""}

    assert BinaryPV.format_value(false, object) == "false"
    assert BinaryPV.format_value(true, object) == "true"
    refute BinaryPV.has_state_texts?(object)
  end

  test "format_value returns nil for non-binary objects" do
    assert BinaryPV.format_value(true, %{type: :analog_value}) == nil
  end

  test "object_fields extracts non-empty texts" do
    assert BinaryPV.object_fields(%{
             type: :binary_value,
             inactive_text: "Off",
             active_text: "On"
           }) == %{inactive_text: "Off", active_text: "On"}

    assert BinaryPV.object_fields(%{type: :analog_input}) == %{}
  end

  test "state_options labels use inactive/active text when present" do
    options =
      BinaryPV.state_options(%{
        type: :binary_value,
        inactive_text: "Closed",
        active_text: "Open"
      })

    assert options == [
             %{value: true, label: "Open"},
             %{value: false, label: "Closed"}
           ]
  end

  test "state_options falls back to true/false labels" do
    assert BinaryPV.state_options(%{type: :binary_input}) == [
             %{value: true, label: "true"},
             %{value: false, label: "false"}
           ]
  end
end
