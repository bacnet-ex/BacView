defmodule BacView.BACnet.Protocol.WeeklyScheduleEditorTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.{
    BACnetArray,
    BACnetTime,
    DailySchedule,
    DeviceObjectPropertyRef,
    TimeValue
  }

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectsUtility

  alias BacView.BACnet.Protocol.WeeklyScheduleEditor

  @schedule_object %{type: :schedule, instance: 1, name: "Schedule 1"}

  defp weekly_array(opts \\ []) do
    daily =
      Keyword.get(
        opts,
        :daily,
        %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 30, second: 0, hundredth: 0},
              value: {:real, 22.0}
            }
          ]
        }
      )

    BACnetArray.new(7, daily)
  end

  defp weekly_prop(array) do
    %{
      property: :weekly_schedule,
      property_name: "Weekly Schedule",
      value: array
    }
  end

  test "matches? for schedule weekly_schedule property" do
    assert WeeklyScheduleEditor.matches?(weekly_prop(weekly_array()), @schedule_object)
    refute WeeklyScheduleEditor.matches?(weekly_prop(weekly_array()), %{type: :analog_value})
    refute WeeklyScheduleEditor.matches?(%{property: :present_value, value: 1}, @schedule_object)
  end

  test "from_bacnet returns seven weekday drafts" do
    draft = WeeklyScheduleEditor.from_bacnet(weekly_array())

    assert length(draft.days) == 7

    assert Enum.map(draft.days, & &1.index) ==
             Enum.map(WeeklyScheduleEditor.weekdays(), & &1.index)

    assert hd(draft.days).label == "Montag"
    assert [entry] = hd(draft.days).entries
    assert entry.time == "08:30"
    assert String.starts_with?(entry.value, "22")
  end

  test "to_bacnet round-trips draft with fixed size seven" do
    array = weekly_array()
    draft = WeeklyScheduleEditor.from_bacnet(array)

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, :real)
    assert BACnetArray.size(decoded) == 7
    assert {:ok, %DailySchedule{schedule: [%TimeValue{}]}} = BACnetArray.get_item(decoded, 1)
  end

  test "add and remove entries within a day" do
    draft = WeeklyScheduleEditor.from_bacnet(weekly_array())
    monday = hd(draft.days)
    monday = WeeklyScheduleEditor.add_entry(monday, :real)
    assert length(monday.entries) == 2

    [first | _] = monday.entries
    monday = WeeklyScheduleEditor.remove_entry(monday, first.id)
    assert length(monday.entries) == 1
  end

  test "apply_day_entries accepts flattened single-entry form params" do
    monday = hd(WeeklyScheduleEditor.from_bacnet(weekly_array()).days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"time" => "23:00", "id" => "1-0", "value" => "22"},
               :real
             )

    assert [entry] = updated.entries
    assert entry.time == "23:00"
    assert entry.value == "22"
  end

  test "apply_day_entries accepts list form params" do
    monday = hd(WeeklyScheduleEditor.from_bacnet(weekly_array()).days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               [%{"id" => "1-0", "time" => "23:00", "value" => "22"}],
               :real
             )

    assert [entry] = updated.entries
    assert entry.time == "23:00"
  end

  test "apply_day_entries accepts HH:MM:SS time values from time inputs" do
    monday = hd(WeeklyScheduleEditor.from_bacnet(weekly_array()).days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "23:00:00", "value" => "22"}},
               :real
             )

    assert [entry] = updated.entries
    assert entry.time == "23:00:00"
  end

  test "apply_day_entries accepts HH:MM:SS.hh hundredth precision" do
    monday = hd(WeeklyScheduleEditor.from_bacnet(weekly_array()).days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "08:15:30.45", "value" => "22"}},
               :real
             )

    assert [entry] = updated.entries
    assert entry.time == "08:15:30.45"
  end

  test "to_bacnet preserves seconds and hundredths in schedule entries" do
    array = weekly_array(daily: %DailySchedule{schedule: []})
    draft = WeeklyScheduleEditor.from_bacnet(array)
    monday = hd(draft.days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "06:30:15.12", "value" => "21.5"}},
               :real
             )

    draft = %{draft | days: [updated | tl(draft.days)]}

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, :real)

    assert {:ok,
            %DailySchedule{
              schedule: [
                %TimeValue{
                  time: %BACnetTime{hour: 6, minute: 30, second: 15, hundredth: 12},
                  value: %Encoding{type: :real}
                }
              ]
            }} = BACnetArray.get_item(decoded, 1)
  end

  test "from_bacnet formats seconds and hundredths for editing" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 9, minute: 5, second: 40, hundredth: 7},
              value: {:real, 1.0}
            }
          ]
        }
      )

    draft = WeeklyScheduleEditor.from_bacnet(array)
    [entry] = hd(draft.days).entries

    assert entry.time == "09:05:40.07"
  end

  test "to_bacnet sorts entries by full BACnet time precision" do
    array = weekly_array(daily: %DailySchedule{schedule: []})
    draft = WeeklyScheduleEditor.from_bacnet(array)
    monday = hd(draft.days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{
                 "0" => %{"id" => "1-0", "time" => "08:00:01", "value" => "2"},
                 "1" => %{"id" => "1-1", "time" => "08:00:00.50", "value" => "1"}
               },
               :real
             )

    draft = %{draft | days: [updated | tl(draft.days)]}
    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, :real)

    assert {:ok, %DailySchedule{schedule: schedule}} = BACnetArray.get_item(decoded, 1)

    assert Enum.map(schedule, fn %TimeValue{time: time, value: %Encoding{type: :real, value: v}} ->
             {time.second, time.hundredth, v}
           end) == [{0, 50, 1.0}, {1, 0, 2.0}]
  end

  test "rejects invalid time in day entries" do
    monday = hd(WeeklyScheduleEditor.from_bacnet(weekly_array()).days)

    assert {:error, :invalid_schedule_time} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "99:00", "value" => "1"}},
               :real
             )

    assert {:error, :invalid_schedule_time} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "08:00:60", "value" => "1"}},
               :real
             )

    assert {:error, :invalid_schedule_time} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "08:00:00.1234", "value" => "1"}},
               :real
             )
  end

  test "json round-trip preserves seven elements" do
    array = weekly_array()

    assert {:ok, json} = WeeklyScheduleEditor.encode_json(array)
    assert {:ok, decoded} = WeeklyScheduleEditor.decode_json(json, array)
    assert BACnetArray.size(decoded) == 7
  end

  test "json rejects wrong element count for fixed weekly schedule" do
    array = weekly_array()

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
             WeeklyScheduleEditor.decode_json(json, array)
  end

  test "infer_value_kind uses analog references as real" do
    array = weekly_array(daily: %DailySchedule{schedule: []})

    properties = [
      %{
        property: :list_of_object_property_references,
        value:
          BACnetArray.from_list(
            [
              %DeviceObjectPropertyRef{
                object_identifier: %ObjectIdentifier{type: :analog_value, instance: 12},
                property_identifier: :present_value,
                property_array_index: nil,
                device_identifier: nil
              }
            ],
            false
          )
      },
      weekly_prop(array)
    ]

    assert :real = WeeklyScheduleEditor.infer_value_kind(properties, array)
  end

  test "infer_value_kind uses multi-state references as unsigned integer" do
    array = weekly_array(daily: %DailySchedule{schedule: []})

    properties = [
      %{
        property: :list_of_object_property_references,
        value:
          BACnetArray.from_list(
            [
              %DeviceObjectPropertyRef{
                object_identifier: %ObjectIdentifier{type: :multi_state_value, instance: 213},
                property_identifier: :present_value,
                property_array_index: nil,
                device_identifier: nil
              }
            ],
            false
          )
      },
      weekly_prop(array)
    ]

    assert :unsigned_integer = WeeklyScheduleEditor.infer_value_kind(properties, array)
  end

  test "to_bacnet encodes unsigned integer values for multi-state schedules" do
    array = weekly_array(daily: %DailySchedule{schedule: []})
    draft = WeeklyScheduleEditor.from_bacnet(array)
    monday = hd(draft.days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "08:00", "value" => "3"}},
               :unsigned_integer
             )

    draft = %{draft | days: [updated | tl(draft.days)]}

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, :unsigned_integer)

    assert {:ok,
            %DailySchedule{
              schedule: [%TimeValue{value: %Encoding{type: :unsigned_integer, value: 3}}]
            }} =
             BACnetArray.get_item(decoded, 1)
  end

  test "align_entry_value_kinds remaps unsigned entries when references imply real" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: %Encoding{
                encoding: :primitive,
                extras: [],
                type: :unsigned_integer,
                value: 22
              }
            }
          ]
        }
      )

    draft =
      array
      |> WeeklyScheduleEditor.from_bacnet()
      |> WeeklyScheduleEditor.align_entry_value_kinds(:real)

    [entry] = hd(draft.days).entries
    assert entry.value_kind == :real

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, :real)

    assert {:ok,
            %DailySchedule{
              schedule: [%TimeValue{value: %Encoding{type: :real, value: 22.0}}]
            }} =
             BACnetArray.get_item(decoded, 1)
  end

  test "align_entry_value_kinds remaps real entries when references imply unsigned integer" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: %Encoding{
                encoding: :primitive,
                extras: [],
                type: :real,
                value: 3.0
              }
            }
          ]
        }
      )

    draft =
      array
      |> WeeklyScheduleEditor.from_bacnet()
      |> WeeklyScheduleEditor.align_entry_value_kinds(:unsigned_integer)

    [entry] = hd(draft.days).entries
    assert entry.value_kind == :unsigned_integer

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, :unsigned_integer)

    assert {:ok,
            %DailySchedule{
              schedule: [%TimeValue{value: %Encoding{type: :unsigned_integer, value: 3}}]
            }} =
             BACnetArray.get_item(decoded, 1)
  end

  test "infer_value_kind prefers weekly schedule entry types over present_value" do
    enum_array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: {:enumerated, :active}
            }
          ]
        }
      )

    properties = [
      %{
        property: :present_value,
        value: %BACnet.Protocol.ApplicationTags.Encoding{
          type: :real,
          value: {:real, 1.0},
          encoding: :primitive,
          extras: []
        }
      },
      weekly_prop(enum_array)
    ]

    assert {:enumerated, :binary_present_value} =
             WeeklyScheduleEditor.infer_value_kind(properties, enum_array)
  end

  test "to_bacnet returns error for invalid values instead of raising" do
    array = weekly_array()
    draft = WeeklyScheduleEditor.from_bacnet(array)
    [monday | rest] = draft.days

    monday = %{
      monday
      | entries: [
          %{id: "1-0", time: "08:30", value: "not-a-number", value_kind: :real}
        ]
    }

    draft = %{draft | days: [monday | rest]}

    assert {:error, :invalid_schedule_value} =
             WeeklyScheduleEditor.to_bacnet(draft, array, :real)
  end

  test "to_bacnet round-trips schedules with null and real values" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: {:real, 22.0}
            },
            %TimeValue{
              time: %BACnetTime{hour: 18, minute: 0, second: 0, hundredth: 0},
              value: {:null, nil}
            }
          ]
        }
      )

    draft = WeeklyScheduleEditor.from_bacnet(array)
    value_kind = WeeklyScheduleEditor.infer_value_kind([], array)

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, value_kind)
    assert {:ok, json} = WeeklyScheduleEditor.encode_json(decoded)
    assert is_binary(json)

    assert {:ok, %DailySchedule{schedule: schedule}} = BACnetArray.get_item(decoded, 1)
    assert length(schedule) == 2

    assert Enum.any?(
             schedule,
             &match?(%TimeValue{value: %Encoding{type: :null, value: nil}}, &1)
           )
  end

  test "from_bacnet handles enumerated Encoding values without crashing" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: %Encoding{
                encoding: :primitive,
                extras: [],
                type: :enumerated,
                value: 0
              }
            }
          ]
        }
      )

    draft = WeeklyScheduleEditor.from_bacnet(array)
    [entry] = hd(draft.days).entries

    assert entry.time == "08:00"
    assert entry.value == "inactive"
    assert entry.value_kind == {:enumerated, :binary_present_value}
  end

  test "to_bacnet round-trips enumerated weekly schedule values" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: {:enumerated, :active}
            }
          ]
        }
      )

    draft = WeeklyScheduleEditor.from_bacnet(array)
    value_kind = WeeklyScheduleEditor.infer_value_kind([], array)

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, value_kind)

    assert {:ok, %DailySchedule{} = daily} = BACnetArray.get_item(decoded, 1)
    assert [%TimeValue{value: %Encoding{type: :enumerated, value: 1}}] = daily.schedule
    assert DailySchedule.valid?(daily)
  end

  test "to_bacnet encodes enumerated values as integer application tags" do
    draft = WeeklyScheduleEditor.from_bacnet(weekly_array(daily: %DailySchedule{schedule: []}))
    monday = hd(draft.days)

    assert {:ok, updated} =
             WeeklyScheduleEditor.apply_day_entries(
               monday,
               %{"0" => %{"id" => "1-0", "time" => "23:00", "value" => "inactive"}},
               {:enumerated, :binary_present_value}
             )

    draft = %{draft | days: [updated | tl(draft.days)]}
    array = weekly_array()

    assert {:ok, decoded} =
             WeeklyScheduleEditor.to_bacnet(draft, array, {:enumerated, :binary_present_value})

    assert {:ok,
            %DailySchedule{schedule: [%TimeValue{value: %Encoding{type: :enumerated, value: 0}}]}} =
             BACnetArray.get_item(decoded, 1)
  end

  test "validate_weekly_array rejects constructed schedule entry values" do
    invalid_daily = %DailySchedule{
      schedule: [
        %TimeValue{
          time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
          value: %Encoding{
            encoding: :constructed,
            extras: [tag_number: 0],
            type: nil,
            value: [real: 5.0]
          }
        }
      ]
    }

    array = BACnetArray.new(7, invalid_daily)

    assert {:error, :invalid_schedule_primitive_value} =
             WeeklyScheduleEditor.validate_weekly_array(array)
  end

  test "validate_weekly_array accepts legacy tuple and primitive encoding values" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: {:real, 22.0}
            },
            %TimeValue{
              time: %BACnetTime{hour: 18, minute: 0, second: 0, hundredth: 0},
              value: %Encoding{
                encoding: :primitive,
                extras: [],
                type: :enumerated,
                value: 1
              }
            }
          ]
        }
      )

    assert :ok = WeeklyScheduleEditor.validate_weekly_array(array)
  end

  test "cast_value_to_property accepts weekly schedule BACnetArray" do
    array =
      weekly_array(
        daily: %DailySchedule{
          schedule: [
            %TimeValue{
              time: %BACnetTime{hour: 8, minute: 0, second: 0, hundredth: 0},
              value: {:enumerated, :active}
            }
          ]
        }
      )

    draft = WeeklyScheduleEditor.from_bacnet(array)
    value_kind = WeeklyScheduleEditor.infer_value_kind([], array)

    assert {:ok, decoded} = WeeklyScheduleEditor.to_bacnet(draft, array, value_kind)

    assert {:ok, encodings} =
             ObjectsUtility.cast_value_to_property(
               %ObjectIdentifier{type: :schedule, instance: 1},
               :weekly_schedule,
               decoded
             )

    assert length(encodings) == 7
    assert Enum.all?(encodings, &match?(%Encoding{encoding: :constructed}, &1))
  end
end
