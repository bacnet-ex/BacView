defmodule BacView.BACnet.Protocol.TrendLogNavigationTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{BACnetArray, DeviceObjectPropertyRef, ObjectIdentifier}
  alias BacView.BACnet.Protocol.TrendLogNavigation

  defp ref(type, instance, device_identifier \\ nil) do
    %DeviceObjectPropertyRef{
      device_identifier: device_identifier,
      object_identifier: %ObjectIdentifier{type: type, instance: instance},
      property_identifier: :present_value,
      property_array_index: nil
    }
  end

  defp url_opts(device_id) do
    [device_id: device_id, tab: "objects"]
  end

  test "finds trend logs that reference the current object" do
    ai = %{type: :analog_input, instance: 1, name: "AI-1"}

    trend_log = %{
      type: :trend_log,
      instance: 2,
      name: "Trend 2",
      log_property_refs: [ref(:analog_input, 1)]
    }

    trend_log_multiple = %{
      type: :trend_log_multiple,
      instance: 3,
      name: "Trend 3",
      log_property_refs: [ref(:binary_input, 4)]
    }

    targets =
      TrendLogNavigation.targets_for_object(
        7,
        ai,
        [ai, trend_log, trend_log_multiple],
        [],
        7,
        url_opts(7)
      )

    assert length(targets) == 1
    assert %{type: :trend_log, instance: 2, label: "Trend 2 (trend_log:2)"} = hd(targets)
    assert hd(targets).href =~ "/devices/7/objects/trend_log/2"
  end

  test "finds referenced objects for trend log objects on the same device" do
    ai = %{type: :analog_input, instance: 1, name: "AI-1"}
    trend_log = %{type: :trend_log, instance: 2, name: "Trend 2"}

    properties = [
      %{
        property: :log_device_object_property,
        value: ref(:analog_input, 1)
      }
    ]

    targets =
      TrendLogNavigation.targets_for_object(
        7,
        trend_log,
        [ai, trend_log],
        properties,
        7,
        url_opts(7)
      )

    assert [%{type: :analog_input, instance: 1, label: "AI-1 (analog_input:1)"}] = targets
    assert hd(targets).href =~ "/devices/7/objects/analog_input/1"
  end

  test "ignores referenced objects on another device" do
    trend_log = %{type: :trend_log, instance: 2, name: "Trend 2"}

    properties = [
      %{
        property: :log_device_object_property,
        value:
          ref(
            :analog_input,
            1,
            %ObjectIdentifier{type: :device, instance: 99}
          )
      }
    ]

    targets =
      TrendLogNavigation.targets_for_object(
        7,
        trend_log,
        [%{type: :analog_input, instance: 1, name: "AI-1"}],
        properties,
        7,
        url_opts(7)
      )

    assert targets == []
  end

  test "includes referenced objects when device identifier matches current device" do
    ai = %{type: :analog_input, instance: 1, name: "AI-1"}
    trend_log = %{type: :trend_log, instance: 2, name: "Trend 2"}

    properties = [
      %{
        property: :log_device_object_property,
        value:
          ref(
            :analog_input,
            1,
            %ObjectIdentifier{type: :device, instance: 7}
          )
      }
    ]

    targets =
      TrendLogNavigation.targets_for_object(
        7,
        trend_log,
        [ai, trend_log],
        properties,
        7,
        url_opts(7)
      )

    assert [%{type: :analog_input, instance: 1}] = targets
  end

  test "returns multiple referenced objects for trend log multiple" do
    ai = %{type: :analog_input, instance: 1, name: "AI-1"}
    bi = %{type: :binary_input, instance: 2, name: "BI-2"}
    trend_log = %{type: :trend_log_multiple, instance: 5, name: "Trend 5"}

    {:ok, array} =
      BACnetArray.new()
      |> then(&BACnetArray.set_item(&1, 1, ref(:analog_input, 1)))
      |> then(fn {:ok, array} -> BACnetArray.set_item(array, 2, ref(:binary_input, 2)) end)

    properties = [
      %{
        property: :log_device_object_property,
        value: array
      }
    ]

    targets =
      TrendLogNavigation.targets_for_object(
        7,
        trend_log,
        [ai, bi, trend_log],
        properties,
        7,
        url_opts(7)
      )

    assert length(targets) == 2
    assert Enum.map(targets, &{&1.type, &1.instance}) == [{:analog_input, 1}, {:binary_input, 2}]
  end

  test "skips referenced objects that are not present on the device" do
    trend_log = %{type: :trend_log, instance: 2, name: "Trend 2"}

    properties = [
      %{
        property: :log_device_object_property,
        value: ref(:analog_input, 99)
      }
    ]

    targets =
      TrendLogNavigation.targets_for_object(
        7,
        trend_log,
        [trend_log],
        properties,
        7,
        url_opts(7)
      )

    assert targets == []
  end
end
