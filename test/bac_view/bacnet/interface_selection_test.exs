defmodule BacView.BACnet.InterfaceSelectionTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.InterfaceSelection

  test "resolve returns ok tuple with interface and options for ipv4" do
    assert {:ok, %{interface: interface, options: options}} =
             InterfaceSelection.resolve("ipv4", "nonexistent-interface-xyz")

    assert is_binary(interface)
    assert options != []
    assert Enum.any?(options, &(&1.value == interface))
  end

  test "resolve picks first option when saved interface is missing" do
    case InterfaceSelection.options_for("ipv4") do
      [first | _] = options ->
        assert {:ok, %{interface: interface, options: ^options}} =
                 InterfaceSelection.resolve("ipv4", "missing-interface")

        assert interface == first.value

      [] ->
        assert {:ok, %{interface: "lo", options: [%{value: "lo"} | _]}} =
                 InterfaceSelection.resolve("ipv4", nil)
    end
  end

  test "resolve returns error when no serial ports are available for mstp" do
    case InterfaceSelection.options_for("mstp") do
      [] ->
        assert {:error, :no_serial_ports, %{options: [], interface: nil}} =
                 InterfaceSelection.resolve("mstp", nil)

      [_ | _] ->
        assert {:ok, %{interface: interface}} = InterfaceSelection.resolve("mstp", nil)
        assert is_binary(interface)
    end
  end
end
