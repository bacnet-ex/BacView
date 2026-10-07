defmodule BacView.BACnet.PropertyExportTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.DailySchedule
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.TimeValue
  alias BacView.BACnet.PropertyExport
  alias BacViewWeb.Gettext, as: GettextBackend

  test "exports selected properties and leaves missing ones empty or null" do
    groups = [
      group(10, [
        object(:analog_input, 1, %{
          object_name: "Temp",
          present_value: 21.5,
          _unknown_properties: %{512 => "vendor"}
        }),
        object(:binary_input, 2, %{object_name: "Pump", present_value: true})
      ]),
      group(12, [
        object(:analog_value, 3, %{object_name: "Setpoint", description: "Room"})
      ])
    ]

    keys = [
      "10|analog_input|1",
      "10|binary_input|2",
      "12|analog_value|3"
    ]

    properties = [:present_value, :description, 512]

    assert {:ok,
            %{filename: "bacview-properties.csv", mime: "text/csv; charset=utf-8", content: csv}} =
             PropertyExport.export(groups, keys, properties, :csv)

    csv_lines = [
      ~s("device_instance";"object_type";"object_instance";"present_value";"description";"512"),
      ~s("10";"analog_input";"1";"21.5";;"vendor"),
      ~s("10";"binary_input";"2";"true";;),
      ~s("12";"analog_value";"3";;"Room";)
    ]

    assert csv == Enum.join(csv_lines, "\n")

    assert {:ok, %{filename: "bacview-properties.json", content: json}} =
             PropertyExport.export(groups, keys, properties, :json)

    assert {:ok, decoded} = Jason.decode(json)

    assert decoded == [
             %{
               "device_instance" => 10,
               "object_type" => "analog_input",
               "object_instance" => 1,
               "properties" => %{
                 "present_value" => 21.5,
                 "description" => nil,
                 "512" => "vendor"
               }
             },
             %{
               "device_instance" => 10,
               "object_type" => "binary_input",
               "object_instance" => 2,
               "properties" => %{
                 "present_value" => true,
                 "description" => nil,
                 "512" => nil
               }
             },
             %{
               "device_instance" => 12,
               "object_type" => "analog_value",
               "object_instance" => 3,
               "properties" => %{
                 "present_value" => nil,
                 "description" => "Room",
                 "512" => nil
               }
             }
           ]
  end

  test "writes a weekly schedule as one weekday per line and keeps scalars as text" do
    time = %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0}

    entry = %TimeValue{
      time: time,
      value: %Encoding{encoding: :primitive, extras: [], type: :unsigned_integer, value: 2}
    }

    day = %DailySchedule{schedule: [entry]}
    schedule = BACnetArray.from_list([day, day])

    groups = [
      group(7, [
        object(:schedule, 1, %{
          weekly_schedule: schedule,
          local_time: time,
          object_identifier: %ObjectIdentifier{type: :schedule, instance: 1}
        })
      ])
    ]

    keys = ["7|schedule|1"]
    properties = [:weekly_schedule, :local_time, :object_identifier]

    assert {:ok, %{content: csv}} = PropertyExport.export(groups, keys, properties, :csv)
    assert {:ok, %{content: json}} = PropertyExport.export(groups, keys, properties, :json)

    assert csv =~ "\"Montag: 00:00:00=2\nDienstag: 00:00:00=2\""
    assert csv =~ "\"00:00:00.000\""
    assert csv =~ "\"schedule:1\""

    assert {:ok, [decoded_row]} = Jason.decode(json)

    assert decoded_row["properties"]["weekly_schedule"] == [
             %{
               "schedule" => [
                 %{
                   "time" => %{"hour" => 0, "minute" => 0, "second" => 0, "hundredth" => 0},
                   "value" => 2
                 }
               ]
             },
             %{
               "schedule" => [
                 %{
                   "time" => %{"hour" => 0, "minute" => 0, "second" => 0, "hundredth" => 0},
                   "value" => 2
                 }
               ]
             }
           ]
  end

  test "uses multistate and binary texts and drops a zero time fraction" do
    on_the_hour = %BACnetTime{hour: 6, minute: 0, second: 0, hundredth: 0}
    precise = %BACnetTime{hour: 6, minute: 0, second: 1, hundredth: 50}
    unsigned = %Encoding{encoding: :primitive, extras: [], type: :unsigned_integer, value: 2}
    active = %Encoding{encoding: :primitive, extras: [], type: :enumerated, value: :active}

    multistate =
      BACnetArray.from_list([
        %DailySchedule{schedule: [%TimeValue{time: on_the_hour, value: unsigned}]},
        %DailySchedule{schedule: []},
        %DailySchedule{
          schedule: [%TimeValue{time: precise, value: unsigned}]
        }
      ])

    assert {:ok, %{content: multistate_csv}} =
             PropertyExport.export(
               [
                 group(7, [
                   object(:schedule, 1, %{
                     weekly_schedule: multistate,
                     state_text: ["Aus", "Ein", "Auto"],
                     number_of_states: 3
                   })
                 ])
               ],
               ["7|schedule|1"],
               [:weekly_schedule],
               :csv
             )

    assert multistate_csv =~
             "Montag: 06:00:00=2 (Ein)\nDienstag: -\nMittwoch: 06:00:01.500=2 (Ein)"

    reference = %BACnet.Protocol.DeviceObjectPropertyRef{
      object_identifier: %ObjectIdentifier{type: :binary_value, instance: 3},
      property_identifier: :present_value,
      property_array_index: nil,
      device_identifier: nil
    }

    binary_day = %DailySchedule{schedule: [%TimeValue{time: on_the_hour, value: active}]}

    assert {:ok, %{content: binary_csv}} =
             PropertyExport.export(
               [
                 group(7, [
                   object(:schedule, 1, %{
                     weekly_schedule: BACnetArray.from_list([binary_day]),
                     list_of_object_property_references: BACnetArray.from_list([reference])
                   }),
                   object(:binary_value, 3, %{active_text: "Open", inactive_text: "Closed"})
                 ])
               ],
               ["7|schedule|1"],
               [:weekly_schedule],
               :csv
             )

    assert binary_csv =~ "Montag: 06:00:00=Open"
    refute binary_csv =~ "UNSIGNED INTEGER"
    refute binary_csv =~ "active"
  end

  test "localizes weekly schedule weekday names" do
    previous = Gettext.get_locale(GettextBackend)
    Gettext.put_locale(GettextBackend, "en")
    on_exit(fn -> Gettext.put_locale(GettextBackend, previous) end)

    time = %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0}

    entry = %TimeValue{
      time: time,
      value: %Encoding{encoding: :primitive, extras: [], type: :unsigned_integer, value: 2}
    }

    assert {:ok, %{content: csv}} =
             PropertyExport.export(
               [
                 group(7, [
                   object(:schedule, 1, %{
                     weekly_schedule: BACnetArray.from_list([%DailySchedule{schedule: [entry]}])
                   })
                 ])
               ],
               ["7|schedule|1"],
               [:weekly_schedule],
               :csv
             )

    assert csv =~ "Monday: 00:00:00=2"
  end

  test "quotes csv cells that contain the separator" do
    groups = [group(4, [object(:analog_value, 1, %{object_name: "A;B \"C\""})])]

    assert {:ok, %{content: csv}} =
             PropertyExport.export(groups, ["4|analog_value|1"], [:object_name], :csv)

    assert csv =~ ~s("A;B ""C""")
  end

  test "uses the bacstack property list plus unknown properties" do
    assert {:ok, object} =
             BACnet.Protocol.ObjectTypes.AnalogInput.create(1, "Temp", %{present_value: 21.5})

    object = %{object | _unknown_properties: %{512 => "vendor"}}
    ids = PropertyExport.property_ids(object)

    assert :present_value in ids
    assert :object_name in ids
    assert 512 in ids
    refute :not_a_property in ids

    entries =
      PropertyExport.entries(
        %{id: 8, instance: 8, name: "AHU"},
        [{%ObjectIdentifier{type: :analog_input, instance: 1}, object}]
      )

    assert [%{key: "8|analog_input|1", property_ids: property_ids}] = entries
    assert 512 in property_ids
    refute :not_a_property in property_ids
  end

  test "filter_objects and filter_properties match search text without dropping other entries" do
    objects = [
      %{
        key: "10|analog_input|1",
        name: "Temp",
        type: :analog_input,
        type_label: "Analog Input",
        instance: 1,
        device_name: "AHU",
        device_instance: 10
      },
      %{
        key: "10|binary_input|2",
        name: "Pump",
        type: :binary_input,
        type_label: "Binary Input",
        instance: 2,
        device_name: "AHU",
        device_instance: 10
      }
    ]

    assert [%{key: "10|binary_input|2"}] =
             PropertyExport.filter_objects(objects, "", "pump")

    assert [%{key: "10|analog_input|1"}] =
             PropertyExport.filter_objects(objects, "analog_input", "ahu")

    assert objects == PropertyExport.filter_objects(objects, "", "  ")

    properties = [
      %{id: :present_value, token: "present_value", label: "present value"},
      %{id: :description, token: "description", label: "description"}
    ]

    assert [%{id: :description}] = PropertyExport.filter_properties(properties, "DESC")
    assert properties == PropertyExport.filter_properties(properties, "")
  end

  test "filter_entries keeps only the requested type" do
    objects = [
      %{key: "1", type: :analog_input},
      %{key: "2", type: :binary_input}
    ]

    assert [%{key: "2"}] = PropertyExport.filter_entries(objects, "binary_input")
    assert objects == PropertyExport.filter_entries(objects, "")
    assert objects == PropertyExport.filter_entries(objects, "missing_type")
  end

  test "rejects an export without devices, objects, or properties" do
    group = group(1, [object(:analog_input, 1, %{present_value: 1})])

    assert {:error, :no_devices} =
             PropertyExport.export([], ["1|analog_input|1"], [:present_value], :csv)

    assert {:error, :no_properties_selected} =
             PropertyExport.export([group], ["1|analog_input|1"], [], :csv)

    assert {:error, :no_objects} = PropertyExport.export([group], [], [:present_value], :json)
  end

  defp group(instance, scanned) do
    %{
      device_id: instance,
      device_instance: instance,
      device_name: "Device #{instance}",
      scanned: scanned
    }
  end

  defp object(type, instance, properties) do
    {%ObjectIdentifier{type: type, instance: instance}, properties}
  end
end
