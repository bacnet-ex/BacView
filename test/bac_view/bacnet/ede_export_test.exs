defmodule BacView.BACnet.EdeExportTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.EdeExport

  @meta [
    project_name: "TestProject",
    version: "2.0.0",
    author: "Tester",
    include_state_texts: false,
    object_types: [
      :analog_input,
      :analog_value,
      :binary_input,
      :binary_value,
      :device,
      :file,
      :multi_state_value
    ]
  ]

  test "export_from_scanned builds EDE header from provided meta" do
    scanned = [
      {%ObjectIdentifier{type: :analog_input, instance: 3},
       %{
         object_name: "AI-Temp",
         description: "Room temperature",
         min_present_value: 0,
         max_present_value: 100,
         high_limit: 24,
         low_limit: 18,
         cov_increment: 0.5,
         present_value: 21.5,
         priority_array: %{}
       }}
    ]

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 42, @meta)
    assert file.filename == "TestProject_EDE.csv"
    assert file.mime =~ "text/csv"

    assert file.content =~ "PROJECT_NAME;TestProject"
    assert file.content =~ "VERSION_OF_REFERENCEFILE;2.0.0"
    assert file.content =~ "AUTHOR_OF_LAST_CHANGE;Tester"
    assert file.content =~ "AI-Temp;42;AI-Temp;0;3;Room temperature"
    # object type 0 = analog_input, device instance 42, object instance 3
    assert file.content =~ ";Y;Y;"
    # settable true (priority_array), supports COV true
    refute file.content =~ "State Text Reference"
  end

  test "include_state_texts exports StateTexts for multistate and binary" do
    scanned = [
      {%ObjectIdentifier{type: :multi_state_value, instance: 1},
       %{
         object_name: "Mode",
         state_text: ["Off", "Auto", "Manual"],
         number_of_states: 3
       }},
      {%ObjectIdentifier{type: :binary_input, instance: 2},
       %{
         object_name: "Door",
         inactive_text: "Closed",
         active_text: "Open"
       }},
      {%ObjectIdentifier{type: :multi_state_value, instance: 3},
       %{
         object_name: "Mode2",
         state_text: ["Off", "Auto", "Manual"],
         number_of_states: 3
       }}
    ]

    assert {:ok, %{files: files}} =
             EdeExport.export_from_scanned(
               scanned,
               10,
               Keyword.put(@meta, :include_state_texts, true)
             )

    assert length(files) == 2
    ede = Enum.find(files, &String.ends_with?(&1.filename, "_EDE.csv"))
    state = Enum.find(files, &String.ends_with?(&1.filename, "_StateTexts.csv"))

    assert ede
    assert state
    assert state.filename == "TestProject_StateTexts.csv"

    # Both multistate share the same ref; binary gets its own
    assert ede.content =~ "Mode;10;Mode;19;1"
    assert ede.content =~ "Door;10;Door;3;2"

    # state-text-reference column values appear as numbers in object rows
    assert state.content =~ "Off"
    assert state.content =~ "Auto"
    assert state.content =~ "Manual"
    assert state.content =~ "Closed"
    assert state.content =~ "Open"
  end

  test "does not emit StateTexts file when option is false" do
    scanned = [
      {%ObjectIdentifier{type: :binary_value, instance: 1},
       %{object_name: "Flag", inactive_text: "No", active_text: "Yes"}}
    ]

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 1, @meta)
    assert String.ends_with?(file.filename, "_EDE.csv")
  end

  test "exports unit_code for objects with units" do
    scanned = [
      {%ObjectIdentifier{type: :analog_value, instance: 5},
       %{object_name: "AV", units: :degrees_celsius}},
      {%ObjectIdentifier{type: :analog_input, instance: 1},
       %{object_name: "AI", units: :percent}},
      {%ObjectIdentifier{type: :integer_value, instance: 3}, %{object_name: "IV", units: :hours}},
      {%ObjectIdentifier{type: :positive_integer_value, instance: 4},
       %{object_name: "PIV", units: :seconds}},
      {%ObjectIdentifier{type: :accumulator, instance: 6},
       %{object_name: "ACC", units: :kilowatt_hours}},
      {%ObjectIdentifier{type: :pulse_converter, instance: 7},
       %{object_name: "PC", units: :cubic_meters}},
      {%ObjectIdentifier{type: :binary_input, instance: 2},
       %{object_name: "BI", units: :degrees_celsius}}
    ]

    meta =
      Keyword.update!(@meta, :object_types, fn types ->
        types ++ [:integer_value, :positive_integer_value, :accumulator, :pulse_converter]
      end)

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 1, meta)

    data_rows =
      file.content
      |> String.split("\r\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.reject(&String.contains?(&1, "PROJECT_NAME"))
      |> Enum.reject(&String.contains?(&1, "VERSION_"))
      |> Enum.reject(&String.contains?(&1, "TIMESTAMP_"))
      |> Enum.reject(&String.contains?(&1, "AUTHOR_"))
      |> Enum.reject(&String.contains?(&1, "VERSION_OF_LAYOUT"))

    av_cells = Enum.find(data_rows, &String.starts_with?(&1, "AV;")) |> String.split(";")
    ai_cells = Enum.find(data_rows, &String.starts_with?(&1, "AI;")) |> String.split(";")
    iv_cells = Enum.find(data_rows, &String.starts_with?(&1, "IV;")) |> String.split(";")
    piv_cells = Enum.find(data_rows, &String.starts_with?(&1, "PIV;")) |> String.split(";")
    acc_cells = Enum.find(data_rows, &String.starts_with?(&1, "ACC;")) |> String.split(";")
    pc_cells = Enum.find(data_rows, &String.starts_with?(&1, "PC;")) |> String.split(";")
    bi_cells = Enum.find(data_rows, &String.starts_with?(&1, "BI;")) |> String.split(";")

    # unit-code is second-to-last standard optional column (index 14)
    assert Enum.at(av_cells, 14) == "62"
    assert Enum.at(ai_cells, 14) == "98"
    assert Enum.at(iv_cells, 14) == "71"
    assert Enum.at(piv_cells, 14) == "73"
    assert Enum.at(acc_cells, 14) == "19"
    assert Enum.at(pc_cells, 14) == "80"
    assert Enum.at(bi_cells, 14) in [nil, ""]
  end

  test "objects without units leave unit_code empty" do
    scanned = [
      {%ObjectIdentifier{type: :analog_input, instance: 1}, %{object_name: "AI"}},
      {%ObjectIdentifier{type: :integer_value, instance: 2}, %{object_name: "IV"}}
    ]

    meta = Keyword.put(@meta, :object_types, [:analog_input, :integer_value])

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 1, meta)

    data_rows =
      file.content
      |> String.split("\r\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.reject(&String.contains?(&1, "PROJECT_NAME"))
      |> Enum.reject(&String.contains?(&1, "VERSION_"))
      |> Enum.reject(&String.contains?(&1, "TIMESTAMP_"))
      |> Enum.reject(&String.contains?(&1, "AUTHOR_"))
      |> Enum.reject(&String.contains?(&1, "VERSION_OF_LAYOUT"))

    for row <- data_rows do
      cells = String.split(row, ";")
      assert Enum.at(cells, 14) in [nil, ""]
    end
  end

  test "rejects blank project name and non-semver version" do
    scanned = [
      {%ObjectIdentifier{type: :device, instance: 1}, %{object_name: "Dev"}}
    ]

    assert {:error, :invalid_project_name} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "  ",
               version: "1.0.0",
               author: "A",
               object_types: [:device]
             )

    assert {:error, :invalid_version} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "P",
               version: "",
               author: "A",
               object_types: [:device]
             )

    assert {:error, :invalid_version} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "P",
               version: "1",
               author: "A",
               object_types: [:device]
             )

    assert {:error, :invalid_version} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "P",
               version: "1.0",
               author: "A",
               object_types: [:device]
             )
  end

  test "rejects empty object type selection" do
    scanned = [
      {%ObjectIdentifier{type: :device, instance: 1}, %{object_name: "Dev"}}
    ]

    assert {:error, :no_object_types_selected} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "P",
               version: "1.0.0",
               author: "A",
               object_types: []
             )
  end

  test "filters objects by selected object types" do
    scanned = [
      {%ObjectIdentifier{type: :analog_input, instance: 1}, %{object_name: "AI"}},
      {%ObjectIdentifier{type: :file, instance: 2}, %{object_name: "F"}},
      {%ObjectIdentifier{type: :binary_input, instance: 3}, %{object_name: "BI"}}
    ]

    assert {:ok, %{files: [file]}} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "P",
               version: "1.0.0",
               author: "A",
               object_types: [:analog_input, :binary_input]
             )

    assert file.content =~ "AI;"
    assert file.content =~ "BI;"
    refute file.content =~ "F;"
  end

  test "available_object_types and default_selected exclude file and structured_view" do
    scanned = [
      {%ObjectIdentifier{type: :file, instance: 1}, %{}},
      {%ObjectIdentifier{type: :structured_view, instance: 4}, %{}},
      {%ObjectIdentifier{type: :analog_input, instance: 2}, %{}},
      {%ObjectIdentifier{type: :analog_input, instance: 3}, %{}}
    ]

    available = EdeExport.available_object_types(scanned)
    types = Enum.map(available, & &1.type)

    assert :file in types
    assert :structured_view in types
    assert :analog_input in types
    assert Enum.find(available, &(&1.type == :analog_input)).count == 2

    selected = EdeExport.default_selected_object_types(available)
    assert :analog_input in selected
    refute :file in selected
    refute :structured_view in selected
  end

  test "empty object_name falls back and keynames stay unique" do
    scanned = [
      {%ObjectIdentifier{type: :analog_input, instance: 1}, %{}},
      {%ObjectIdentifier{type: :analog_input, instance: 2}, %{object_name: "analog_input_1"}}
    ]

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 7, @meta)
    assert file.content =~ "analog_input_1;7;analog_input_1;0;1"
    assert file.content =~ "analog_input_1 (analog_input:2);7;analog_input_1;0;2"
  end

  test "skips unmapped object types" do
    scanned = [
      {%ObjectIdentifier{type: :not_a_real_type, instance: 9}, %{object_name: "X"}},
      {%ObjectIdentifier{type: :analog_input, instance: 1}, %{object_name: "AI"}}
    ]

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 1, @meta)
    assert file.content =~ "AI;"
    refute file.content =~ "X;"
  end

  test "float coercion for integer limit fields" do
    scanned = [
      {%ObjectIdentifier{type: :analog_input, instance: 1},
       %{
         object_name: "AI",
         min_present_value: 0,
         max_present_value: 50,
         high_limit: 40,
         low_limit: 10
       }}
    ]

    assert {:ok, %{files: [file]}} = EdeExport.export_from_scanned(scanned, 1, @meta)
    assert file.content =~ "AI;1;AI;0;1;;;0.0;50.0"
    assert file.content =~ ";40.0;10.0;"
  end

  test "export/2 returns error when device is unknown" do
    assert {:error, reason} =
             EdeExport.export(9_999_991,
               project_name: "P",
               version: "1.0.0",
               author: "A",
               object_types: [:device]
             )

    assert reason in [:device_not_loaded, :no_objects]
  end

  test "filename prefix sanitizes project name" do
    scanned = [
      {%ObjectIdentifier{type: :device, instance: 1}, %{object_name: "Dev"}}
    ]

    assert {:ok, %{files: [file]}} =
             EdeExport.export_from_scanned(scanned, 1,
               project_name: "My Project/Name",
               version: "1.0.0",
               author: "",
               object_types: [:device]
             )

    assert file.filename == "My_Project_Name_EDE.csv"
  end
end
