defmodule BacView.BACnet.SerialPortsTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.SerialPorts

  test "list returns string port names from enumerate map shape" do
    for %{value: value, label: label} <- SerialPorts.list() do
      assert is_binary(value)
      assert is_binary(label)
      assert value == label
    end
  end
end
