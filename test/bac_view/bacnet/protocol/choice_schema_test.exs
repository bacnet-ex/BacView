defmodule BacView.BACnet.Protocol.ChoiceSchemaTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.CalendarEntry
  alias BACnet.Protocol.NameValue
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Protocol.SpecialEvent

  alias BacView.BACnet.Protocol.ChoiceSchema
  alias BacView.BACnet.Protocol.CollectionItemTemplate

  describe "analyze/1 tagged CHOICE" do
    test "CalendarEntry exposes date / date_range / week_n_day arms" do
      schema = ChoiceSchema.analyze(CalendarEntry)
      assert length(schema.choices) == 1

      [choice] = schema.choices
      assert choice.kind == :tagged
      assert choice.discriminant_key == :type
      assert Enum.map(choice.arms, & &1.id) == [:date, :date_range, :week_n_day]
      assert Enum.all?(choice.arms, &(&1.field == &1.id))
    end

    test "Recipient exposes device and address arms" do
      schema = ChoiceSchema.analyze(Recipient)
      [choice] = schema.choices
      assert choice.kind == :tagged
      arm_ids = Enum.map(choice.arms, & &1.id) |> Enum.sort()
      assert arm_ids == [:address, :device]
    end

    test "BACnetTimestamp exposes time / sequence_number / datetime" do
      schema = ChoiceSchema.analyze(BACnetTimestamp)
      [choice] = schema.choices
      assert Enum.map(choice.arms, & &1.id) == [:time, :sequence_number, :datetime]
    end
  end

  describe "analyze/1 inline CHOICE" do
    test "NameValue value is Encoding | nil only (no date_time arm)" do
      schema = ChoiceSchema.analyze(NameValue)
      assert schema.plain_fields == [:name]

      [choice] = schema.choices
      assert choice.kind == :inline
      assert choice.source_field == :value
      assert choice.payload_key == :value
      assert choice.discriminant_key == :value_kind

      arm_ids = Enum.map(choice.arms, & &1.id)
      assert arm_ids == [:none, :encoding]
      refute :date_time in arm_ids
      refute Enum.any?(choice.arms, &(&1.id == :date_time))
    end

    test "SpecialEvent period is calendar_entry | calendar_reference" do
      schema = ChoiceSchema.analyze(SpecialEvent)
      [choice] = schema.choices
      assert choice.kind == :inline
      assert choice.discriminant_key == :period_kind
      assert choice.payload_key == :period

      arm_ids = Enum.map(choice.arms, & &1.id)
      assert :calendar_entry in arm_ids
      assert :calendar_reference in arm_ids
      refute :object_identifier in arm_ids

      ref = Enum.find(choice.arms, &(&1.id == :calendar_reference))
      assert ref.label == "Calendar Reference"
    end
  end

  describe "active_arm_id/2 and apply_arm/3" do
    test "tagged Recipient switches arms and nils inactive payload" do
      schema = ChoiceSchema.analyze(Recipient)
      [choice] = schema.choices
      recipient = CollectionItemTemplate.blank_recipient(:address)

      assert ChoiceSchema.active_arm_id(recipient, choice) == :address

      device = ChoiceSchema.apply_arm(recipient, choice, :device)
      assert device.type == :device
      assert %ObjectIdentifier{type: :device, instance: 0} = device.device
      assert device.address == nil
      assert ChoiceSchema.active_arm_id(device, choice) == :device

      address = ChoiceSchema.apply_arm(device, choice, :address)
      assert address.type == :address
      assert %RecipientAddress{} = address.address
      assert address.device == nil
    end

    test "inline NameValue switches none / encoding" do
      schema = ChoiceSchema.analyze(NameValue)
      [choice] = schema.choices
      nv = %NameValue{name: "tag", value: nil}

      assert ChoiceSchema.active_arm_id(nv, choice) == :none

      with_encoding = ChoiceSchema.apply_arm(nv, choice, :encoding)
      assert %Encoding{} = with_encoding.value
      assert ChoiceSchema.active_arm_id(with_encoding, choice) == :encoding

      cleared = ChoiceSchema.apply_arm(with_encoding, choice, :none)
      assert cleared.value == nil
    end

    test "SpecialEvent period switches calendar entry and reference" do
      schema = ChoiceSchema.analyze(SpecialEvent)
      [choice] = schema.choices

      event = %SpecialEvent{
        period: CollectionItemTemplate.blank_calendar_entry(:date),
        list: [],
        priority: 1
      }

      assert ChoiceSchema.active_arm_id(event, choice) == :calendar_entry

      ref = ChoiceSchema.apply_arm(event, choice, :calendar_reference)
      assert %ObjectIdentifier{type: :calendar, instance: 0} = ref.period
      assert ChoiceSchema.active_arm_id(ref, choice) == :calendar_reference
    end
  end

  describe "parse_arm_id/2" do
    test "accepts known arms and rejects unknown" do
      schema = ChoiceSchema.analyze(NameValue)
      [choice] = schema.choices

      assert {:ok, :encoding} = ChoiceSchema.parse_arm_id("encoding", choice)
      assert {:error, :invalid_enum} = ChoiceSchema.parse_arm_id("date_time", choice)
      assert {:error, :empty_value} = ChoiceSchema.parse_arm_id("  ", choice)
    end
  end

  describe "options/1" do
    test "golden NameValue options match current UI" do
      schema = ChoiceSchema.analyze(NameValue)
      [choice] = schema.choices

      assert ChoiceSchema.options(choice) == [
               %{value: :none, label: "None"},
               %{value: :encoding, label: "Encoding"}
             ]
    end
  end
end
