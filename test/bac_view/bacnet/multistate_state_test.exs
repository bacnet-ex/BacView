defmodule BacView.BACnet.Protocol.MultistateStateTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.BACnetArray
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyFormatter

  describe "format_present_value/2" do
    test "appends active state text for multistate objects" do
      object = %{
        type: :multi_state_value,
        number_of_states: 3,
        state_text: ["Off", "On", "Auto"]
      }

      assert MultistateState.format_present_value(2, object) == "2 (On)"
      assert PropertyFormatter.format_present_value(2, object) == "2 (On)"
    end

    test "omits parentheses when state text is blank" do
      object = %{
        type: :multi_state_input,
        number_of_states: 2,
        state_text: ["", "On"]
      }

      assert MultistateState.format_present_value(1, object) == "1"
      assert MultistateState.format_present_value(2, object) == "2 (On)"
    end

    test "formats relinquish_default values with active state text" do
      object = %{
        type: :multi_state_output,
        number_of_states: 2,
        state_text: ["Off", "On"]
      }

      assert MultistateState.format_present_value(1, object) == "1 (Off)"
    end
  end

  describe "state_value_property?/1" do
    test "includes present_value and relinquish_default" do
      assert MultistateState.state_value_property?(:present_value)
      assert MultistateState.state_value_property?(:relinquish_default)
      refute MultistateState.state_value_property?(:number_of_states)
    end
  end

  describe "state_options/1" do
    test "returns valid state labels only" do
      object = %{
        type: :multi_state_output,
        number_of_states: 3,
        state_text: BACnetArray.from_list(["Off", "On", "Auto"])
      }

      assert MultistateState.state_options(object) == [
               %{value: 1, label: "1 (Off)"},
               %{value: 2, label: "2 (On)"},
               %{value: 3, label: "3 (Auto)"}
             ]
    end
  end
end
