defmodule BacView.BACnet.Protocol.PropertyDisplayTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    BACnetArray,
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    CovSubscription,
    LimitEnable,
    ObjectIdentifier,
    ObjectPropertyRef,
    PriorityArray,
    Recipient,
    RecipientAddress,
    StatusFlags
  }

  alias BACnet.Protocol.ApplicationTags.Encoding

  alias BacView.BACnet.Protocol.PropertyDisplay

  test "expands status flags into labeled boolean fields" do
    flags = %StatusFlags{
      in_alarm: false,
      fault: true,
      overridden: false,
      out_of_service: false
    }

    display = PropertyDisplay.build(flags)

    assert display.kind == :struct
    assert length(display.fields) == 4

    fault = Enum.find(display.fields, &(&1.key == :fault))
    assert fault.label == "Fault"
    assert fault.kind == :boolean
    assert fault.value == true
  end

  test "shows all 16 priority array slots" do
    pa = %PriorityArray{priority_8: 21.5, priority_16: 99.0}
    display = PropertyDisplay.build(pa)

    assert display.kind == :priority_array
    assert length(display.items) == 16
    assert Enum.find(display.items, &(&1.key == 8)).formatted == "21.5"
    assert Enum.find(display.items, &(&1.key == 1)).formatted == "-"
  end

  test "expands limit enable for writing" do
    enable = %LimitEnable{low_limit_enable: true, high_limit_enable: false}
    display = PropertyDisplay.build(enable)

    assert display.kind == :struct
    assert Enum.all?(display.fields, &(&1.kind == :boolean))
  end

  test "formats recipient address binaries as hex in display tree" do
    subscription = %CovSubscription{
      recipient: %Recipient{
        type: :address,
        device: nil,
        address: %RecipientAddress{network: 0, address: <<192, 168, 1, 73, 186, 192>>}
      },
      recipient_process: 1,
      monitored_object_property: %ObjectPropertyRef{
        object_identifier: %ObjectIdentifier{type: :analog_input, instance: 1},
        property_identifier: :present_value,
        property_array_index: nil
      },
      issue_confirmed_notifications: false,
      time_remaining: 60,
      cov_increment: 1.0
    }

    display = PropertyDisplay.build([subscription])

    assert display.kind == :list
    [item] = display.items
    recipient = Enum.find(item.fields, &(&1.key == :recipient))
    address_field = recipient.fields |> Enum.find(&(&1.key == :address)) |> Map.get(:fields)
    address = Enum.find(address_field, &(&1.key == :address))

    assert address.formatted == "192.168.1.73:47808"
    assert Jason.encode!(display.formatted)
    assert Jason.encode!(address.formatted)
  end

  test "formats primitive Encoding inline as type and value" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [],
      type: :real,
      value: 13.5
    }

    display = PropertyDisplay.build(encoding)

    assert display.kind == :scalar
    assert display.formatted == "REAL: 13.5"
    assert display.fields == []
  end

  test "formats constructed Encoding as expandable struct" do
    encoding = %Encoding{
      encoding: :constructed,
      extras: [tag_number: 0],
      type: nil,
      value: [real: 5.0]
    }

    display = PropertyDisplay.build(encoding)

    assert display.kind == :struct
    assert display.fields != []
    assert Enum.any?(display.fields, &(&1.key == :encoding))
    assert Enum.any?(display.fields, &(&1.key == :value))
  end

  test "labels BACnetArray as array and plain lists as list" do
    array_display = PropertyDisplay.build(BACnetArray.from_list([1, 2]))
    list_display = PropertyDisplay.build([1, 2])

    assert array_display.kind == :array
    assert list_display.kind == :list
    assert length(array_display.items) == 2
    assert length(list_display.items) == 2
  end

  test "formats BACnetDateTime as scalar instead of struct" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
      time: %BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 0}
    }

    display = PropertyDisplay.build(datetime)

    assert display.kind == :scalar
    assert display.formatted == "27.06.2026 17:17:43.000"
    assert display.fields == []
  end

  test "brief_summary uses short labels for nested values" do
    display = %{
      kind: :struct,
      formatted: "long",
      fields: [
        %{label: "A", formatted: "1"},
        %{label: "B", formatted: "2"}
      ],
      items: []
    }

    assert PropertyDisplay.brief_summary(display) =~ "2"
    assert PropertyDisplay.brief_summary(%{kind: :array, items: [1, 2, 3]}) =~ "3"
  end
end
