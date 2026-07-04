defmodule BacView.BACnet.DeviceServicesTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.DeviceServices

  describe "parse_enable_disable/1" do
    test "accepts known states" do
      assert {:ok, :enable} = DeviceServices.parse_enable_disable("enable")
      assert {:ok, :disable} = DeviceServices.parse_enable_disable("disable")

      assert {:ok, :disable_initiation} =
               DeviceServices.parse_enable_disable("disable_initiation")
    end

    test "rejects unknown state" do
      assert {:error, :invalid_state} = DeviceServices.parse_enable_disable("invalid")
    end
  end

  describe "parse_reinitialized_state/1" do
    test "accepts warm and cold start" do
      assert {:ok, :warmstart} = DeviceServices.parse_reinitialized_state("warmstart")
      assert {:ok, :coldstart} = DeviceServices.parse_reinitialized_state("coldstart")
    end
  end

  describe "parse_time_duration/1" do
    test "empty means indefinite" do
      assert {:ok, nil} = DeviceServices.parse_time_duration("")
      assert {:ok, nil} = DeviceServices.parse_time_duration("indefinite")
    end

    test "parses minutes" do
      assert {:ok, 30} = DeviceServices.parse_time_duration("30")
    end
  end

  describe "parse_password/1" do
    test "blank becomes nil" do
      assert DeviceServices.parse_password("") == nil
      assert DeviceServices.parse_password("   ") == nil
    end

    test "keeps non-empty password" do
      assert DeviceServices.parse_password("secret") == "secret"
    end
  end
end
