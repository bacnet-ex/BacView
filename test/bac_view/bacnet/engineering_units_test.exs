defmodule BacView.BACnet.Protocol.EngineeringUnitsTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.EngineeringUnits

  describe "symbol/1" do
    test "returns compact symbols for common units" do
      assert EngineeringUnits.symbol(:degrees_celsius) == "°C"
      assert EngineeringUnits.symbol(:degrees_fahrenheit) == "°F"
      assert EngineeringUnits.symbol(:percent) == "%"
      assert EngineeringUnits.symbol(:kilowatts) == "kW"
      assert EngineeringUnits.symbol(:pascals) == "Pa"
    end

    test "returns empty string for no units" do
      assert EngineeringUnits.symbol(:no_units) == ""
      assert EngineeringUnits.symbol(nil) == ""
    end

    test "passes through pre-formatted strings" do
      assert EngineeringUnits.symbol("°C") == "°C"
    end
  end

  describe "label/1" do
    test "returns human-readable text for engineering units" do
      assert EngineeringUnits.label(:degrees_celsius) == "Degrees Celsius"
      assert EngineeringUnits.label(:percent_relative_humidity) == "Percent Relative Humidity"
    end

    test "handles no units and nil" do
      assert EngineeringUnits.label(:no_units) == "No units"
      assert EngineeringUnits.label(nil) == "—"
    end
  end
end
