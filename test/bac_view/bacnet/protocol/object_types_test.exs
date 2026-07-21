defmodule BacView.BACnet.Protocol.ObjectTypesTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.ObjectTypes

  test "supported?/1 is true for implementable standard types" do
    assert ObjectTypes.supported?(:analog_input)
    assert ObjectTypes.supported?(:device)
    assert ObjectTypes.supported?(:binary_value)
  end

  test "supported?/1 is false for proprietary integers and unknown atoms" do
    refute ObjectTypes.supported?(900)
    refute ObjectTypes.supported?(128)
    refute ObjectTypes.supported?(:definitely_not_a_real_object_type_xyz)
  end
end
