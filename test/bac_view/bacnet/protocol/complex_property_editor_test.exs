defmodule BacView.BACnet.Protocol.ComplexPropertyEditorTest do
  use ExUnit.Case, async: true

  alias Plug.Conn.Query

  alias BACnet.Protocol.{
    BACnetArray,
    BACnetDate,
    BACnetDateTime,
    BACnetTime,
    CalendarEntry,
    DailySchedule,
    Destination,
    DeviceObjectPropertyRef,
    EventMessageTexts,
    EventParameters,
    NameValue,
    ObjectIdentifier,
    ObjectPropertyRef,
    Recipient,
    RecipientAddress,
    TimeValue
  }

  alias BACnet.Protocol.ApplicationTags.Encoding

  alias BacView.BACnet.Protocol.{CollectionItemTemplate, ComplexPropertyEditor, PropertyFormatter}

  test "plug keeps dotted field names as flat keys" do
    assert %{"field" => %{"date.day" => "27", "time.hour" => "8"}} =
             Query.decode("field[date.day]=27&field[time.hour]=8")
  end

  test "form fields include enum dropdowns for ObjectPropertyRef" do
    ref = %ObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :binary_value, instance: 189},
      property_identifier: :present_value,
      property_array_index: nil
    }

    fields = ComplexPropertyEditor.form_fields(ref)
    type_field = Enum.find(fields, &(&1.path == "object_identifier.type"))
    property_field = Enum.find(fields, &(&1.path == "property_identifier"))

    assert type_field.enum_options != nil
    assert Enum.any?(type_field.enum_options, &(&1.value == :binary_value))
    assert property_field.enum_options != nil
    assert Enum.any?(property_field.enum_options, &(&1.value == :present_value))
  end

  test "form fields keep enum dropdowns when enumerated field value is out of range" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [tag_number: 0],
      type: 99,
      value: 42.0
    }

    fields = ComplexPropertyEditor.form_fields(encoding)
    type_field = Enum.find(fields, &(&1.path == "type"))

    assert type_field.enum_options != nil
    assert type_field.value == "99"
    assert Enum.any?(type_field.enum_options, &(&1.value == :real))
  end

  test "applies enum field changes via form fields" do
    ref = %ObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :binary_value, instance: 189},
      property_identifier: :present_value,
      property_array_index: nil
    }

    params = %{
      "field" => %{
        "object_identifier.type" => "analog_value",
        "object_identifier.instance" => "189",
        "property_identifier" => "status_flags",
        "property_array_index" => ""
      }
    }

    assert {:ok, decoded} = ComplexPropertyEditor.apply_form_fields(params, ref)
    assert decoded.object_identifier.type == :analog_value
    assert decoded.property_identifier == :status_flags
  end

  test "encodes empty BACnetArray as empty JSON list" do
    array = BACnetArray.new()

    assert {:ok, json} = ComplexPropertyEditor.encode_json(array)
    assert json =~ "[]"
    refute json =~ "undefined"
  end

  test "form fields include enum dropdowns for DeviceObjectPropertyRef" do
    ref = %DeviceObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :multi_state_value, instance: 213},
      property_identifier: :present_value,
      property_array_index: nil,
      device_identifier: nil
    }

    fields = ComplexPropertyEditor.form_fields(ref)
    type_field = Enum.find(fields, &(&1.path == "object_identifier.type"))
    property_field = Enum.find(fields, &(&1.path == "property_identifier"))

    assert type_field.enum_options != nil
    assert Enum.any?(type_field.enum_options, &(&1.value == :multi_state_value))
    assert property_field.enum_options != nil
    assert Enum.any?(property_field.enum_options, &(&1.value == :present_value))
  end

  test "round-trips DeviceObjectPropertyRef list in empty BACnetArray as JSON" do
    array = BACnetArray.new()

    json = """
    [
      {
        "device_identifier": null,
        "object_identifier": {
          "instance": 213,
          "type": "multi_state_value"
        },
        "property_array_index": null,
        "property_identifier": "present_value"
      }
    ]
    """

    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, array)
    assert BACnetArray.size(decoded) == 1

    assert {:ok, %DeviceObjectPropertyRef{} = ref} = BACnetArray.get_item(decoded, 1)
    assert ref.object_identifier.type == :multi_state_value
    assert ref.object_identifier.instance == 213
    assert ref.property_identifier == :present_value
    assert ref.device_identifier == nil
    assert ref.property_array_index == nil

    assert {:ok, roundtrip_json} = ComplexPropertyEditor.encode_json(decoded)
    assert {:ok, roundtrip} = ComplexPropertyEditor.decode_json(roundtrip_json, decoded)
    assert {:ok, ^ref} = BACnetArray.get_item(roundtrip, 1)
  end

  test "round-trips multiple DeviceObjectPropertyRef items in BACnetArray as JSON" do
    array = BACnetArray.new()

    json = """
    [
      {
        "device_identifier": null,
        "object_identifier": {"instance": 1, "type": "analog_value"},
        "property_array_index": null,
        "property_identifier": "present_value"
      },
      {
        "device_identifier": null,
        "object_identifier": {"instance": 2, "type": "binary_value"},
        "property_array_index": null,
        "property_identifier": "present_value"
      }
    ]
    """

    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, array)
    assert BACnetArray.size(decoded) == 2
    assert {:ok, first} = BACnetArray.get_item(decoded, 1)
    assert {:ok, second} = BACnetArray.get_item(decoded, 2)
    assert first.object_identifier.instance == 1
    assert second.object_identifier.instance == 2
    assert second.object_identifier.type == :binary_value
  end

  test "JSON multi-item decode keeps all entries when first equals existing template item" do
    # Regression: rebuild used the first existing element as :array default; any
    # decoded item equal to that default was omitted by sparse_to_list / write cast.
    existing = %DeviceObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :binary_value, instance: 258},
      property_identifier: :present_value,
      property_array_index: nil,
      device_identifier: nil
    }

    template = BACnetArray.from_list([existing], false)

    json = """
    [
      {
        "device_identifier": null,
        "object_identifier": {"instance": 258, "type": "binary_value"},
        "property_array_index": null,
        "property_identifier": "present_value"
      },
      {
        "device_identifier": null,
        "object_identifier": {"instance": 358, "type": "binary_value"},
        "property_array_index": null,
        "property_identifier": "present_value"
      }
    ]
    """

    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, template)
    assert BACnetArray.size(decoded) == 2

    dense = BACnetArray.to_list(decoded)
    assert length(dense) == 2
    assert Enum.map(dense, & &1.object_identifier.instance) == [258, 358]

    obj = %ObjectIdentifier{type: :schedule, instance: 1}

    assert {:ok, encodings} =
             BACnet.Protocol.ObjectsUtility.cast_value_to_property(
               obj,
               :list_of_object_property_references,
               decoded
             )

    # Two refs × (object_identifier + property_identifier) context tags
    assert length(encodings) == 4
  end

  test "adds blank DeviceObjectPropertyRef to empty BACnetArray via property hint" do
    array = BACnetArray.new()

    assert ComplexPropertyEditor.form_fields(array) == []

    assert ComplexPropertyEditor.can_add_item?(array,
             property: :list_of_object_property_references
           )

    assert {:ok, updated} =
             ComplexPropertyEditor.add_item(array, property: :list_of_object_property_references)

    assert BACnetArray.size(updated) == 1
    assert {:ok, %DeviceObjectPropertyRef{} = ref} = BACnetArray.get_item(updated, 1)
    assert ref.object_identifier.type == :analog_input
    assert ref.property_identifier == :present_value

    fields = ComplexPropertyEditor.form_fields(updated)
    assert Enum.any?(fields, &(&1.path == "0.object_identifier.type"))
    assert {:items, [%{index: 0}]} = ComplexPropertyEditor.form_field_groups(fields)
  end

  test "adds and removes multiple collection items and applies form fields for all" do
    array = BACnetArray.new()

    assert {:ok, one} =
             ComplexPropertyEditor.add_item(array, property: :list_of_object_property_references)

    assert {:ok, two} =
             ComplexPropertyEditor.add_item(one, property: :list_of_object_property_references)

    assert BACnetArray.size(two) == 2

    fields = ComplexPropertyEditor.form_fields(two)
    params = ComplexPropertyEditor.initial_field_params(fields)

    params =
      Map.merge(params, %{
        "0.object_identifier.type" => "analog_value",
        "0.object_identifier.instance" => "10",
        "1.object_identifier.type" => "binary_value",
        "1.object_identifier.instance" => "20"
      })

    assert {:ok, applied} = ComplexPropertyEditor.apply_form_fields(%{"field" => params}, two)
    assert BACnetArray.size(applied) == 2
    assert {:ok, first} = BACnetArray.get_item(applied, 1)
    assert {:ok, second} = BACnetArray.get_item(applied, 2)
    assert first.object_identifier == %ObjectIdentifier{type: :analog_value, instance: 10}
    assert second.object_identifier == %ObjectIdentifier{type: :binary_value, instance: 20}

    assert {:ok, removed} = ComplexPropertyEditor.remove_item(applied, 0)
    assert BACnetArray.size(removed) == 1
    assert {:ok, only} = BACnetArray.get_item(removed, 1)
    assert only.object_identifier.instance == 20
  end

  test "adds Destination entries to empty recipient_list" do
    assert {:ok, list} = ComplexPropertyEditor.add_item([], property: :recipient_list)
    assert [%Destination{} = dest] = list
    assert dest.recipient.type == :address

    assert {:ok, two} = ComplexPropertyEditor.add_item(list, property: :recipient_list)
    assert length(two) == 2
  end

  test "adds blank NameValue to empty tags BACnetArray via schema" do
    array = BACnetArray.new()

    assert ComplexPropertyEditor.can_add_item?(array,
             property: :tags,
             object_type: :analog_input
           )

    assert {:ok, updated} =
             ComplexPropertyEditor.add_item(array,
               property: :tags,
               object_type: :analog_input
             )

    assert BACnetArray.size(updated) == 1
    assert {:ok, %NameValue{name: "", value: nil}} = BACnetArray.get_item(updated, 1)

    fields = ComplexPropertyEditor.form_fields(updated)
    assert Enum.any?(fields, &(&1.path == "0.name"))
    assert Enum.any?(fields, &(&1.path == "0.value_kind"))
    refute Enum.any?(fields, &String.starts_with?(&1.path, "0.value."))
  end

  test "adds blank string items to empty bit_text array via schema" do
    array = BACnetArray.new()

    assert {:ok, updated} =
             ComplexPropertyEditor.add_item(array,
               property: :bit_text,
               object_type: :bitstring_value
             )

    assert BACnetArray.size(updated) == 1
    assert {:ok, ""} = BACnetArray.get_item(updated, 1)
  end

  test "Recipient type change rebuilds active branch fields" do
    dest = CollectionItemTemplate.blank_destination()
    assert dest.recipient.type == :address

    fields = ComplexPropertyEditor.form_fields(dest)
    type_field = Enum.find(fields, &(&1.path == "recipient.type"))
    assert type_field.enum_options != nil
    assert Enum.any?(fields, &String.starts_with?(&1.path, "recipient.address"))
    refute Enum.any?(fields, &String.starts_with?(&1.path, "recipient.device"))

    assert {:ok, updated} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"recipient.type" => "device"}},
               dest
             )

    assert updated.recipient.type == :device
    assert %ObjectIdentifier{type: :device, instance: 0} = updated.recipient.device
    assert updated.recipient.address == nil

    updated_fields = ComplexPropertyEditor.form_fields(updated)
    assert Enum.any?(updated_fields, &String.starts_with?(&1.path, "recipient.device"))
    refute Enum.any?(updated_fields, &String.starts_with?(&1.path, "recipient.address"))
  end

  test "Recipient type change wins over stale previous-branch fields in same submit" do
    dest = CollectionItemTemplate.blank_destination()

    # Browser still has address fields in the form when type is changed.
    params = %{
      "field" => %{
        "recipient.address.network" => "99",
        "recipient.address.address" => "broadcast",
        "recipient.type" => "device"
      }
    }

    assert {:ok, updated} = ComplexPropertyEditor.apply_form_fields(params, dest)
    assert updated.recipient.type == :device
    assert updated.recipient.address == nil
    assert %ObjectIdentifier{type: :device} = updated.recipient.device
  end

  test "CalendarEntry type change swaps date / range / week_n_day fields" do
    entry = CollectionItemTemplate.blank_calendar_entry(:date)
    fields = ComplexPropertyEditor.form_fields(entry)
    assert Enum.any?(fields, &String.starts_with?(&1.path, "date."))
    refute Enum.any?(fields, &String.starts_with?(&1.path, "date_range."))

    assert {:ok, range_entry} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"type" => "date_range"}},
               entry
             )

    assert %CalendarEntry{type: :date_range, date: nil, week_n_day: nil} = range_entry
    assert range_entry.date_range != nil

    range_fields = ComplexPropertyEditor.form_fields(range_entry)
    assert Enum.any?(range_fields, &String.starts_with?(&1.path, "date_range."))
    refute Enum.any?(range_fields, &(&1.path == "date" or String.starts_with?(&1.path, "date.")))
  end

  test "NameValue value_kind picker switches none / encoding only" do
    nv = %NameValue{name: "exhaust", value: nil}
    fields = ComplexPropertyEditor.form_fields(nv)
    kind_field = Enum.find(fields, &(&1.path == "value_kind"))
    assert kind_field.value == "none"
    assert kind_field.enum_options != nil
    refute Enum.any?(kind_field.enum_options, &(&1.value == "date_time"))

    assert {:ok, with_encoding} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"value_kind" => "encoding"}},
               nv
             )

    assert %Encoding{encoding: :primitive, type: :character_string, value: ""} =
             with_encoding.value

    encoding_fields = ComplexPropertyEditor.form_fields(with_encoding)
    assert Enum.any?(encoding_fields, &(&1.path == "value.encoding"))

    # BACnetDateTime is no longer a valid NameValue value in bacstack.
    assert {:error, _reason} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"value_kind" => "date_time"}},
               with_encoding
             )
  end

  @event_params_opts [property: :event_parameters, object_type: :event_enrollment]

  test "event_parameters form includes kind picker for multi-struct union" do
    cov = %EventParameters.ChangeOfValue{
      time_delay: 5,
      increment: 1.0,
      bitmask: nil,
      time_delay_normal: nil
    }

    fields = ComplexPropertyEditor.form_fields(cov, @event_params_opts)
    kind_field = Enum.find(fields, &(&1.path == "kind"))

    assert kind_field != nil
    assert kind_field.value == "change_of_value"
    assert kind_field.label == "Type"
    assert Enum.any?(kind_field.enum_options, &(&1.value == :change_of_bitstring))
    assert Enum.any?(kind_field.enum_options, &(&1.value == :change_of_value))
    assert Enum.any?(kind_field.enum_options, &(&1.value == :none))

    # Payload fields of the current arm remain editable.
    assert Enum.any?(fields, &(&1.path == "time_delay"))
    assert Enum.any?(fields, &(&1.path == "increment"))
  end

  test "event_parameters kind switch replaces whole value (ChangeOfValue → ChangeOfBitstring)" do
    cov = %EventParameters.ChangeOfValue{
      time_delay: 5,
      increment: 1.0,
      bitmask: nil,
      time_delay_normal: nil
    }

    assert {:ok, cob} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"kind" => "change_of_bitstring"}},
               cov,
               @event_params_opts
             )

    assert %EventParameters.ChangeOfBitstring{} = cob
    assert cob.time_delay == 0

    fields = ComplexPropertyEditor.form_fields(cob, @event_params_opts)
    kind_field = Enum.find(fields, &(&1.path == "kind"))
    assert kind_field.value == "change_of_bitstring"
    assert Enum.any?(fields, &(&1.path == "bitmask"))
    assert Enum.any?(fields, &(&1.path == "time_delay"))
    # Empty list payload (alarm_values) has no leaf form fields until items exist.
    refute Enum.any?(fields, &(&1.path == "increment"))
  end

  test "event_parameters kind switch ignores stale previous-arm fields" do
    cov = %EventParameters.ChangeOfValue{
      time_delay: 5,
      increment: 1.0,
      bitmask: nil,
      time_delay_normal: nil
    }

    # LiveView resubmits all previous branch fields with the new kind.
    assert {:ok, cob} =
             ComplexPropertyEditor.apply_form_fields(
               %{
                 "field" => %{
                   "kind" => "change_of_bitstring",
                   "increment" => "1.0",
                   "time_delay" => "5"
                 }
               },
               cov,
               @event_params_opts
             )

    assert %EventParameters.ChangeOfBitstring{time_delay: 0} = cob
  end

  test "event_parameters without property opts has no root kind picker" do
    cov = %EventParameters.ChangeOfValue{
      time_delay: 5,
      increment: 1.0,
      bitmask: nil,
      time_delay_normal: nil
    }

    fields = ComplexPropertyEditor.form_fields(cov)
    refute Enum.any?(fields, &(&1.path == "kind"))
  end

  test "NameValue encoding fields survive resubmitted unchanged value_kind" do
    # LiveView always resubmits value_kind with every field change. Applying it last
    # must not rebuild a blank Encoding and wipe typed values.
    nv = %NameValue{name: "", value: nil}

    assert {:ok, with_kind} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"value_kind" => "encoding"}},
               nv
             )

    array = BACnetArray.from_list([with_kind], false)

    params = %{
      "field" => %{
        "0.name" => "Test",
        "0.value.encoding" => "primitive",
        "0.value.type" => "unsigned_integer",
        "0.value.value" => "42",
        "0.value_kind" => "encoding"
      }
    }

    assert {:ok, updated} = ComplexPropertyEditor.apply_form_fields(params, array)
    assert {:ok, item} = BACnetArray.get_item(updated, 1)
    assert item.name == "Test"
    assert %Encoding{encoding: :primitive, type: :unsigned_integer, value: 42} = item.value
    assert {:ok, _tags} = NameValue.encode(item)
  end

  test "date/time component 0 stays integer 0 and is not coerced to unspecified" do
    time = %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0}

    assert {:ok, updated} =
             ComplexPropertyEditor.apply_form_fields(
               %{
                 "field" => %{
                   "hour" => "0",
                   "minute" => "0",
                   "second" => "0",
                   "hundredth" => "0"
                 }
               },
               time
             )

    assert updated == %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0}

    # Starting from :unspecified (blank date pattern / after kind switch), typing 0
    # must parse as integer — not stay on the atom path.
    date = %BACnetDate{
      year: :unspecified,
      month: :unspecified,
      day: :unspecified,
      weekday: :unspecified
    }

    assert {:ok, date_updated} =
             ComplexPropertyEditor.apply_form_fields(
               %{
                 "field" => %{
                   "year" => "2026",
                   "month" => "1",
                   "day" => "2",
                   "weekday" => "0"
                 }
               },
               date
             )

    assert date_updated.year == 2026
    assert date_updated.month == 1
    assert date_updated.day == 2
    # weekday 0 is invalid in BACnet (1..7) but must remain the integer 0, not :unspecified
    assert date_updated.weekday == 0

    assert {:ok, from_unspecified_time} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"hour" => "0", "minute" => "15"}},
               %BACnetTime{
                 hour: :unspecified,
                 minute: :unspecified,
                 second: :unspecified,
                 hundredth: :unspecified
               }
             )

    assert from_unspecified_time.hour == 0
    assert from_unspecified_time.minute == 15
    assert from_unspecified_time.second == :unspecified

    fields = ComplexPropertyEditor.form_fields(from_unspecified_time)
    hour_field = Enum.find(fields, &(&1.path == "hour"))
    assert hour_field.value == "0"
    refute hour_field.value == "unspecified"
  end

  test "NameValue field order is name, value_kind, then value payload" do
    nv = %NameValue{
      name: "exhaust",
      value: CollectionItemTemplate.blank_encoding()
    }

    paths =
      nv
      |> ComplexPropertyEditor.form_fields()
      |> Enum.map(& &1.path)

    assert paths == [
             "name",
             "value_kind",
             "value.encoding",
             "value.type",
             "value.extras.tag_number",
             "value.value"
           ]

    array = BACnetArray.from_list([nv], false)
    form_fields = ComplexPropertyEditor.form_fields(array)

    assert {:items, [%{index: 0, fields: item_fields}]} =
             ComplexPropertyEditor.form_field_groups(form_fields)

    item_paths = Enum.map(item_fields, & &1.path)
    assert List.first(item_paths) == "0.name"
    assert Enum.at(item_paths, 1) == "0.value_kind"
    # value payload must stay after value_kind (alphabetical sort used to break this)
    kind_idx = Enum.find_index(item_paths, &(&1 == "0.value_kind"))
    value_idx = Enum.find_index(item_paths, &(&1 == "0.value.encoding"))
    assert kind_idx < value_idx
  end

  test "Recipient type appears above address/device payload fields" do
    dest = CollectionItemTemplate.blank_destination()
    paths = dest |> ComplexPropertyEditor.form_fields() |> Enum.map(& &1.path)

    type_idx = Enum.find_index(paths, &(&1 == "recipient.type"))
    assert type_idx != nil

    address_paths =
      Enum.with_index(paths)
      |> Enum.filter(fn {p, _} -> String.starts_with?(p, "recipient.address") end)

    assert address_paths != []
    assert Enum.all?(address_paths, fn {_p, idx} -> type_idx < idx end)
  end

  test "blank NameValue kind change still applies and exposes encoding fields" do
    # Fresh add-entry blank: empty name / other fields must not be validated on kind switch.
    nv = %NameValue{name: "", value: nil}

    params = %{
      "field" => %{
        "name" => "",
        "value_kind" => "encoding"
      }
    }

    assert {:ok, updated} = ComplexPropertyEditor.apply_form_fields(params, nv)
    assert updated.name == ""
    assert %Encoding{type: :character_string, value: ""} = updated.value

    fields = ComplexPropertyEditor.form_fields(updated)
    paths = Enum.map(fields, & &1.path)
    assert "value_kind" in paths
    assert "value.encoding" in paths
    assert "value.type" in paths
    assert "value.value" in paths
  end

  test "kind change ignores failing sibling fields from previous branch" do
    # Previous branch still submits invalid/empty sibling values that would always fail.
    nv = %NameValue{name: "tag", value: nil}

    params = %{
      "field" => %{
        "name" => "",
        "value_kind" => "encoding",
        # Stale / would-be-invalid noise that must not block the kind switch
        "value.value" => "",
        "value.type" => "not_a_type"
      }
    }

    assert {:ok, updated} = ComplexPropertyEditor.apply_form_fields(params, nv)
    assert updated.name == "tag"
    assert %Encoding{encoding: :primitive, type: :character_string} = updated.value
  end

  test "blank NameValue kind change works inside tags collection paths" do
    array = BACnetArray.from_list([%NameValue{name: "", value: nil}], false)

    params = %{
      "field" => %{
        "0.name" => "",
        "0.value_kind" => "encoding"
      }
    }

    assert {:ok, updated} = ComplexPropertyEditor.apply_form_fields(params, array)

    assert {:ok, %NameValue{name: "", value: %Encoding{encoding: :primitive}}} =
             BACnetArray.get_item(updated, 1)

    fields = ComplexPropertyEditor.form_fields(updated)
    assert Enum.any?(fields, &(&1.path == "0.value_kind"))
    assert Enum.any?(fields, &(&1.path == "0.value.encoding"))
    assert Enum.any?(fields, &(&1.path == "0.value.type"))
  end

  test "CollectionItemTemplate resolves tags item type from object schema" do
    assert {:ok, {:struct, NameValue}} =
             CollectionItemTemplate.collection_item_type(:tags, :analog_value)

    assert {:ok, %NameValue{name: "", value: nil}} =
             CollectionItemTemplate.default_item(
               property: :tags,
               object_type: :analog_value
             )
  end

  test "rejects misspelled multistate_value object type in JSON" do
    array = BACnetArray.new()

    json = """
    [
      {
        "device_identifier": null,
        "object_identifier": {
          "instance": 213,
          "type": "multistate_value"
        },
        "property_array_index": null,
        "property_identifier": "present_value"
      }
    ]
    """

    assert {:error, :invalid_enum} = ComplexPropertyEditor.decode_json(json, array)
  end

  test "round-trips ObjectPropertyRef as JSON" do
    ref = %ObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :binary_value, instance: 189},
      property_identifier: :present_value,
      property_array_index: nil
    }

    assert {:ok, json} = ComplexPropertyEditor.encode_json(ref)
    assert {:ok, ^ref} = ComplexPropertyEditor.decode_json(json, ref)
  end

  test "round-trips DailySchedule as JSON" do
    schedule = %DailySchedule{
      schedule: [
        %TimeValue{
          time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
          value: {:real, 22.0}
        }
      ]
    }

    assert {:ok, json} = ComplexPropertyEditor.encode_json(schedule)
    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, schedule)
    assert [%TimeValue{} = item] = decoded.schedule
    assert item.value == {:real, 22.0}
  end

  test "round-trips BACnetDateTime as JSON" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
      time: %BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 13}
    }

    assert {:ok, json} = ComplexPropertyEditor.encode_json(datetime)
    assert {:ok, ^datetime} = ComplexPropertyEditor.decode_json(json, datetime)
  end

  test "rejects unknown JSON keys" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
      time: %BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 13}
    }

    json = """
    {
      "date": {"year": 2026, "month": 6, "day2": 99, "weekday": 6},
      "time": {"hour": 18, "minute": 0, "second": 0, "hundredth": 0}
    }
    """

    assert {:error, {:unknown_json_fields, ["day2"]}} =
             ComplexPropertyEditor.decode_json(json, datetime)
  end

  test "applies EventMessageTexts field changes ignoring LiveView _unused_ keys" do
    texts = %EventMessageTexts{
      to_offnormal: "Alarm",
      to_fault: "Fehlerzustand",
      to_normal: "Normal"
    }

    params = %{
      "field" => %{
        "_unused_to_normal" => "",
        "_unused_to_offnormal" => "",
        "to_fault" => "Fehlerzustand2",
        "to_normal" => "Normal",
        "to_offnormal" => "Alarm"
      }
    }

    assert {:ok, decoded} = ComplexPropertyEditor.apply_form_fields(params, texts)
    assert decoded.to_fault == "Fehlerzustand2"
    assert decoded.to_normal == "Normal"
    assert decoded.to_offnormal == "Alarm"
  end

  test "encodes nil as JSON null in Recipient lists" do
    recipients = [
      %Recipient{
        type: :address,
        address: %RecipientAddress{network: 0, address: :broadcast},
        device: nil
      },
      %Recipient{
        type: :device,
        address: nil,
        device: %ObjectIdentifier{type: :device, instance: 98}
      }
    ]

    assert {:ok, json} = ComplexPropertyEditor.encode_json(recipients)
    assert json =~ "null"
    refute json =~ "\"nil\""
  end

  test "round-trips mixed Recipient list as JSON" do
    recipients = [
      %Recipient{
        type: :address,
        address: %RecipientAddress{network: 0, address: :broadcast},
        device: nil
      },
      %Recipient{
        type: :device,
        address: nil,
        device: %ObjectIdentifier{type: :device, instance: 98}
      },
      %Recipient{
        type: :device,
        address: nil,
        device: %ObjectIdentifier{type: :device, instance: 99}
      }
    ]

    assert {:ok, json} = ComplexPropertyEditor.encode_json(recipients)
    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, recipients)
    assert length(decoded) == 3

    assert [%Recipient{type: :address}, %Recipient{type: :device}, %Recipient{type: :device}] =
             decoded
  end

  test "decodes legacy nil strings in Recipient JSON" do
    recipients = [
      %Recipient{
        type: :address,
        address: %RecipientAddress{network: 0, address: :broadcast},
        device: nil
      },
      %Recipient{
        type: :device,
        address: nil,
        device: %ObjectIdentifier{type: :device, instance: 98}
      }
    ]

    json = """
    [
      {
        "address": {"address": "broadcast", "network": 0},
        "device": "nil",
        "type": "address"
      },
      {
        "address": "nil",
        "device": {"instance": 98, "type": "device"},
        "type": "device"
      }
    ]
    """

    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, recipients)

    assert [%Recipient{type: :address, device: nil}, %Recipient{type: :device, address: nil}] =
             decoded
  end

  test "form fields iterate BACnetArray elements instead of internal storage" do
    array = BACnetArray.from_list(["alpha", "beta"], false)
    fields = ComplexPropertyEditor.form_fields(array)
    paths = Enum.map(fields, & &1.path)

    assert paths == ["0", "1"]
    refute "items" in paths
    refute "fixed_size" in paths
    refute "size" in paths
  end

  test "encodes BACnetArray as JSON without crashing on sparse fixed-size storage" do
    array = %BACnetArray{
      fixed_size: 3,
      items: :array.new(0, default: :empty, fixed: false),
      size: 2
    }

    assert {:ok, json} = ComplexPropertyEditor.encode_json(array)
    assert json =~ "empty"
  end

  test "round-trips variable BACnetArray as JSON" do
    array = BACnetArray.from_list(["one", "two"], false)

    assert {:ok, json} = ComplexPropertyEditor.encode_json(array)
    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, array)
    assert BACnetArray.size(decoded) == 2
    assert {:ok, "one"} = BACnetArray.get_item(decoded, 1)
    assert {:ok, "two"} = BACnetArray.get_item(decoded, 2)
  end

  test "round-trips fixed-size BACnetArray as JSON" do
    array = BACnetArray.new(2, :unset)

    assert {:ok, json} = ComplexPropertyEditor.encode_json(array)
    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, array)
    assert BACnetArray.size(decoded) == 2
    assert BACnetArray.fixed_size?(decoded)
  end

  test "rejects adding elements to fixed-size BACnetArray JSON" do
    array = BACnetArray.new(7, %DailySchedule{schedule: []})

    json = """
    [
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []}
    ]
    """

    assert {:error, {:fixed_bacnet_array_size, 7, 8}} =
             ComplexPropertyEditor.decode_json(json, array)
  end

  test "rejects removing elements from fixed-size BACnetArray JSON" do
    array = BACnetArray.new(7, %DailySchedule{schedule: []})

    json = """
    [
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []},
      {"schedule": []}
    ]
    """

    assert {:error, {:fixed_bacnet_array_size, 7, 6}} =
             ComplexPropertyEditor.decode_json(json, array)
  end

  test "allows changing element count on variable BACnetArray JSON" do
    array = BACnetArray.from_list([%DailySchedule{schedule: []}], false)

    json = """
    [
      {"schedule": []},
      {"schedule": []}
    ]
    """

    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, array)
    assert BACnetArray.size(decoded) == 2
  end

  test "form fields expose all Encoding metadata including tag number" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [tag_number: 0],
      type: :enumerated,
      value: 0
    }

    fields = ComplexPropertyEditor.form_fields(encoding)
    paths = Enum.map(fields, & &1.path)

    assert paths == ["encoding", "type", "extras.tag_number", "value"]

    encoding_field = Enum.find(fields, &(&1.path == "encoding"))
    type_field = Enum.find(fields, &(&1.path == "type"))
    tag_field = Enum.find(fields, &(&1.path == "extras.tag_number"))

    assert encoding_field.enum_options != nil
    assert type_field.enum_options != nil
    assert tag_field.value == "0"

    assert Enum.any?(
             type_field.enum_options,
             &(&1.value == :enumerated and
                 &1.label == PropertyFormatter.encoding_type_label(:enumerated))
           )
  end

  test "round-trips constructed Encoding as JSON preserving metadata" do
    encoding = %Encoding{
      encoding: :constructed,
      extras: [tag_number: 0],
      type: nil,
      value: [real: 5.0]
    }

    assert {:ok, json} = ComplexPropertyEditor.encode_json(encoding)
    assert json =~ "\"encoding\""
    assert json =~ "constructed"
    assert json =~ "tag_number"
    assert {:ok, ^encoding} = ComplexPropertyEditor.decode_json(json, encoding)
  end

  test "round-trips Encoding as JSON with type and value" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [],
      type: :enumerated,
      value: 0
    }

    assert {:ok, json} = ComplexPropertyEditor.encode_json(encoding)
    assert json =~ "\"type\""
    assert json =~ "enumerated"
    assert {:ok, ^encoding} = ComplexPropertyEditor.decode_json(json, encoding)
  end

  test "returns error when switching to tagged encoding without tag number" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [],
      type: :boolean,
      value: true
    }

    params = %{
      "field" => %{
        "encoding" => "tagged",
        "extras.tag_number" => "",
        "type" => "boolean",
        "value" => "true"
      }
    }

    assert {:error, :missing_tag_number} =
             ComplexPropertyEditor.apply_form_fields(params, encoding)
  end

  test "clears tag number error after entering tag for tagged encoding" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [],
      type: :boolean,
      value: true
    }

    invalid_params = %{
      "field" => %{
        "encoding" => "tagged",
        "extras.tag_number" => "",
        "type" => "boolean",
        "value" => "true"
      }
    }

    valid_params = %{
      "field" => %{
        "encoding" => "tagged",
        "extras.tag_number" => "0",
        "type" => "boolean",
        "value" => "true"
      }
    }

    assert {:error, :missing_tag_number} =
             ComplexPropertyEditor.apply_form_fields(invalid_params, encoding)

    assert {:ok, %Encoding{encoding: :tagged, extras: [tag_number: 0]}} =
             ComplexPropertyEditor.apply_form_fields(valid_params, encoding)
  end

  test "allows empty tag number for primitive encodings" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [tag_number: 0],
      type: :boolean,
      value: true
    }

    params = %{
      "field" => %{
        "_unused_encoding" => "",
        "encoding" => "primitive",
        "extras.tag_number" => "",
        "type" => "boolean",
        "value" => "true"
      }
    }

    assert {:ok, decoded} = ComplexPropertyEditor.apply_form_fields(params, encoding)
    assert %Encoding{encoding: :primitive, extras: [], type: :boolean, value: true} = decoded
  end

  test "applies Encoding type and value field changes" do
    encoding = %Encoding{
      encoding: :primitive,
      extras: [],
      type: :enumerated,
      value: 0
    }

    params = %{
      "field" => %{
        "type" => "real",
        "value" => "21.5"
      }
    }

    assert {:ok, decoded} = ComplexPropertyEditor.apply_form_fields(params, encoding)
    assert %Encoding{type: :real, value: 21.5} = decoded
  end

  test "round-trips BACnetDateTime via form fields" do
    datetime = %BACnetDateTime{
      date: %BACnetDate{year: 2026, month: 6, day: 27, weekday: 6},
      time: %BACnetTime{hour: 17, minute: 17, second: 43, hundredth: 13}
    }

    fields = ComplexPropertyEditor.form_fields(datetime)
    params = ComplexPropertyEditor.initial_field_params(fields)

    updated_params =
      Map.merge(params, %{
        "date.day" => "28",
        "time.hour" => "8"
      })

    assert {:ok, decoded} =
             ComplexPropertyEditor.apply_form_fields(%{"field" => updated_params}, datetime)

    assert %BACnetDate{day: 28} = decoded.date
    assert %BACnetTime{hour: 8, minute: 17, second: 43, hundredth: 13} = decoded.time
  end

  test "root IP form fields use a non-empty path so field[] is avoided" do
    assert [%{path: "_", value: "192.168.1.81"}] =
             ComplexPropertyEditor.form_fields({192, 168, 1, 81})

    assert %{"field" => %{"_" => "10.0.0.1"}} =
             Query.decode("field[_]=10.0.0.1")

    assert ComplexPropertyEditor.normalize_field_params(["{192, 168, 1, 81}"]) == %{}
  end

  test "formats and applies IPv4 / IPv6 form fields" do
    ipv4 = {192, 168, 1, 81}
    assert [%{path: "_", value: "192.168.1.81"}] = ComplexPropertyEditor.form_fields(ipv4)

    assert {:ok, {10, 0, 0, 1}} =
             ComplexPropertyEditor.apply_form_fields(%{"field" => %{"_" => "10.0.0.1"}}, ipv4)

    # Legacy inspect form still accepted
    assert {:ok, {192, 168, 1, 82}} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"_" => "{192, 168, 1, 82}"}},
               ipv4
             )

    ipv6 = {0, 0, 0, 0, 0, 0, 0, 1}
    assert [%{path: "_", value: "::1"}] = ComplexPropertyEditor.form_fields(ipv6)

    assert {:ok, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"_" => "2001:db8::1"}},
               ipv6
             )

    assert {:error, :invalid_ip} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"_" => "not-an-ip"}},
               ipv4
             )
  end

  test "applies HostNPort host ip_address tagged field" do
    hnp = %BACnet.Protocol.HostNPort{
      host: {:ip_address, {192, 168, 1, 81}},
      port: 47_808
    }

    fields = ComplexPropertyEditor.form_fields(hnp)
    host_field = Enum.find(fields, &(&1.path == "host"))
    assert host_field.value == "192.168.1.81"

    assert {:ok, updated} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"host" => "10.1.2.3", "port" => "47809"}},
               hnp
             )

    assert updated.host == {:ip_address, {10, 1, 2, 3}}
    assert updated.port == 47_809

    assert {:ok, updated_v6} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"host" => "::1"}},
               hnp
             )

    assert updated_v6.host == {:ip_address, {0, 0, 0, 0, 0, 0, 0, 1}}
  end

  test "round-trips boolean bitstring tuples via form fields and JSON" do
    bits = {true, false, true, false, true}

    assert [%{path: "_", value: "10101"}] = ComplexPropertyEditor.form_fields(bits)

    assert {:ok, {false, true, false, true, false}} =
             ComplexPropertyEditor.apply_form_fields(%{"field" => %{"_" => "01010"}}, bits)

    assert {:ok, json} = ComplexPropertyEditor.encode_json(bits)
    assert Jason.decode!(json) == [true, false, true, false, true]
    assert {:ok, ^bits} = ComplexPropertyEditor.decode_json(json, bits)

    # 4-bit bitstrings must not be treated as IPv4
    four = {true, false, false, true}
    assert {:ok, four_json} = ComplexPropertyEditor.encode_json(four)
    assert Jason.decode!(four_json) == [true, false, false, true]
    assert {:ok, ^four} = ComplexPropertyEditor.decode_json(four_json, four)
  end

  test "JSON-encodes IP tuples so the field editor opens by default" do
    ipv4 = {192, 168, 1, 81}
    assert {:ok, json} = ComplexPropertyEditor.encode_json(ipv4)
    assert json =~ "192.168.1.81"
    assert {:ok, ^ipv4} = ComplexPropertyEditor.decode_json(json, ipv4)

    ipv6 = {0, 0, 0, 0, 0, 0, 0, 1}
    assert {:ok, json_v6} = ComplexPropertyEditor.encode_json(ipv6)
    assert json_v6 =~ "::1"
    assert {:ok, ^ipv6} = ComplexPropertyEditor.decode_json(json_v6, ipv6)

    hnp = %BACnet.Protocol.HostNPort{
      host: {:ip_address, {192, 168, 1, 81}},
      port: 47_808
    }

    assert {:ok, hnp_json} = ComplexPropertyEditor.encode_json(hnp)
    assert {:ok, decoded_hnp} = ComplexPropertyEditor.decode_json(hnp_json, hnp)
    assert decoded_hnp.host == {:ip_address, {192, 168, 1, 81}}
    assert decoded_hnp.port == 47_808
  end

  test "formats BACnet/IP MAC binaries for form fields and JSON" do
    mac = <<192, 168, 1, 120, 186, 192>>
    address = %RecipientAddress{network: 0, address: mac}

    fields = ComplexPropertyEditor.form_fields(address)
    mac_field = Enum.find(fields, &(&1.path == "address"))

    assert mac_field.value == "192.168.1.120:47808"
    # Must be valid UTF-8 so LiveView can put it in an HTML value attribute
    assert String.valid?(mac_field.value)

    assert {:ok, json} = ComplexPropertyEditor.encode_json(address)
    assert json =~ "192.168.1.120:47808"
    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, address)
    assert decoded.address == mac

    assert {:ok, updated} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"address" => "10.0.0.5:47808", "network" => "1"}},
               address
             )

    assert updated.network == 1
    assert updated.address == <<10, 0, 0, 5, 186, 192>>

    assert {:ok, via_hex} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"address" => "C0:A8:01:49:00:00"}},
               address
             )

    assert via_hex.address == <<192, 168, 1, 73, 0, 0>>

    assert {:ok, broadcast} =
             ComplexPropertyEditor.apply_form_fields(
               %{"field" => %{"address" => "broadcast"}},
               address
             )

    assert broadcast.address == :broadcast
  end

  test "round-trips Destination recipient_list with BACnet/IP MAC address" do
    destination = %BACnet.Protocol.Destination{
      recipient: %Recipient{
        type: :address,
        address: %RecipientAddress{network: 0, address: <<192, 168, 1, 120, 186, 192>>},
        device: nil
      },
      process_identifier: 0,
      issue_confirmed_notifications: false,
      transitions: %BACnet.Protocol.EventTransitionBits{
        to_offnormal: true,
        to_fault: true,
        to_normal: true
      },
      valid_days: %BACnet.Protocol.DaysOfWeek{
        monday: true,
        tuesday: true,
        wednesday: true,
        thursday: true,
        friday: true,
        saturday: true,
        sunday: true
      },
      from_time: %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0},
      to_time: %BACnetTime{hour: 23, minute: 59, second: 59, hundredth: 99}
    }

    list = [destination]
    fields = ComplexPropertyEditor.form_fields(list)
    address_field = Enum.find(fields, &(&1.path == "0.recipient.address.address"))

    assert address_field.value == "192.168.1.120:47808"
    assert Enum.all?(fields, &String.valid?(&1.value))

    assert {:ok, json} = ComplexPropertyEditor.encode_json(list)
    assert {:ok, decoded} = ComplexPropertyEditor.decode_json(json, list)

    assert [%BACnet.Protocol.Destination{} = dest] = decoded
    assert dest.recipient.address.address == <<192, 168, 1, 120, 186, 192>>

    draft = ComplexPropertyEditor.initial_field_params(fields)
    assert draft["0.recipient.address.address"] == "192.168.1.120:47808"
    assert Jason.encode!(draft)
  end
end
