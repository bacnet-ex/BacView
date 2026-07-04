defmodule BacViewWeb.ObjectTableTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.StatusFlags
  alias BacViewWeb.ObjectTable

  @objects [
    %{
      type: :analog_input,
      type_label: "AI",
      instance: 1,
      name: "WWSG Temp",
      description: nil
    },
    %{
      type: :trend_log,
      type_label: "TL",
      instance: 2,
      name: "WWSG Trend",
      description: nil
    },
    %{
      type: :binary_value,
      type_label: "BV",
      instance: 3,
      name: "Other",
      description: nil
    }
  ]

  test "filtered_objects applies text search and type filter together" do
    assert ObjectTable.filtered_objects(@objects, "wwsg", []) == Enum.take(@objects, 2)

    assert ObjectTable.filtered_objects(@objects, "wwsg", [:analog_input]) ==
             [Enum.at(@objects, 0)]
  end

  test "filtered_objects excludes objects matching -term tokens" do
    objects = [
      %{type: :analog_input, type_label: "AI", instance: 1, name: "Temp", description: "unused"},
      %{
        type: :analog_input,
        type_label: "AI",
        instance: 2,
        name: "Humidity",
        description: "Room"
      },
      %{type: :binary_value, type_label: "BV", instance: 3, name: "Unused Flag", description: nil}
    ]

    assert Enum.map(ObjectTable.filtered_objects(objects, "-unused", []), & &1.instance) == [2]

    assert Enum.map(ObjectTable.filtered_objects(objects, "analog -unused", []), & &1.instance) ==
             [2]
  end

  test "parse_search_query keeps plain text as a single substring match" do
    assert ObjectTable.parse_search_query("wwsg temp") == %{
             include: ["wwsg temp"],
             exclude: [],
             mode: :substring
           }

    assert ObjectTable.parse_search_query("-unused") == %{
             include: [],
             exclude: ["unused"],
             mode: :tokens
           }
  end

  test "filtered_objects treats \\- as a literal leading minus" do
    objects = [
      %{
        type: :analog_input,
        type_label: "AI",
        instance: 1,
        name: "-unused slot",
        description: nil
      },
      %{type: :analog_input, type_label: "AI", instance: 2, name: "Active", description: "unused"}
    ]

    assert Enum.map(ObjectTable.filtered_objects(objects, "\\-unused", []), & &1.instance) == [1]

    assert ObjectTable.parse_search_query("\\-unused") == %{
             include: ["-unused"],
             exclude: [],
             mode: :tokens
           }
  end

  test "parse_search_query treats \\- tokens as include terms alongside exclusions" do
    assert ObjectTable.parse_search_query("analog \\-unused") == %{
             include: ["analog", "-unused"],
             exclude: [],
             mode: :tokens
           }

    assert ObjectTable.parse_search_query("analog \\-unused -spare") == %{
             include: ["analog", "-unused"],
             exclude: ["spare"],
             mode: :tokens
           }
  end

  test "toggle_type_filter excludes and restores types" do
    available = ObjectTable.available_types(@objects)

    without_trend =
      ObjectTable.toggle_type_filter([], available, :trend_log)

    assert without_trend == [:analog_input, :binary_value]

    restored =
      ObjectTable.toggle_type_filter(without_trend, available, :trend_log)

    assert restored == []
  end

  test "filter_type_only keeps a single type" do
    assert ObjectTable.filter_type_only(:binary_value) == [:binary_value]
  end

  test "available_types groups and sorts object types" do
    assert [
             %{type: :analog_input, count: 1},
             %{type: :binary_value, count: 1},
             %{type: :trend_log, count: 1}
           ] =
             ObjectTable.available_types(@objects)
  end

  test "sorted_objects sorts by name ascending and descending" do
    assert [
             %{name: "Other"},
             %{name: "WWSG Temp"},
             %{name: "WWSG Trend"}
           ] =
             ObjectTable.sorted_objects(@objects, "name", :asc)
             |> Enum.map(&Map.take(&1, [:name]))

    assert [
             %{name: "WWSG Trend"},
             %{name: "WWSG Temp"},
             %{name: "Other"}
           ] =
             ObjectTable.sorted_objects(@objects, "name", :desc)
             |> Enum.map(&Map.take(&1, [:name]))
  end

  test "toggle_sort cycles through ascending and descending" do
    assert ObjectTable.toggle_sort(nil, :asc, "name") == {"name", :asc}
    assert ObjectTable.toggle_sort("name", :asc, "name") == {"name", :desc}
    assert ObjectTable.toggle_sort("name", :desc, "name") == {"name", :asc}
    assert ObjectTable.toggle_sort("name", :desc, "type") == {"type", :asc}
  end

  test "list_objects applies filter and sort together" do
    assert [%{type: :analog_input}, %{type: :trend_log}] =
             ObjectTable.list_objects(@objects, "wwsg", [], [], "type", :asc)
             |> Enum.map(&Map.take(&1, [:type]))
  end

  test "filtered_objects applies status filter" do
    objects = [
      %{
        type: :analog_input,
        instance: 1,
        status_flags: %StatusFlags{
          in_alarm: false,
          fault: true,
          overridden: false,
          out_of_service: false
        }
      },
      %{
        type: :binary_value,
        instance: 2,
        status_flags: %StatusFlags{
          in_alarm: false,
          fault: false,
          overridden: false,
          out_of_service: false
        }
      },
      %{type: :analog_output, instance: 3}
    ]

    assert length(ObjectTable.filtered_objects(objects, "", [], [:fault])) == 1

    assert Enum.sort([2, 3]) ==
             ObjectTable.filtered_objects(objects, "", [], [:none])
             |> Enum.map(& &1.instance)
             |> Enum.sort()
  end

  test "toggle_status_filter excludes and restores flags" do
    objects = [
      %{
        status_flags: %StatusFlags{
          in_alarm: false,
          fault: true,
          overridden: false,
          out_of_service: false
        }
      },
      %{
        status_flags: %StatusFlags{
          in_alarm: false,
          fault: false,
          overridden: false,
          out_of_service: false
        }
      }
    ]

    available = ObjectTable.available_status_flags(objects)

    without_normal =
      ObjectTable.toggle_status_filter([], available, :none)

    assert without_normal == [:fault]

    restored =
      ObjectTable.toggle_status_filter(without_normal, available, :none)

    assert restored == []
  end

  describe "available_types labels" do
    setup do
      Gettext.put_locale(BacViewWeb.Gettext, "en")
      on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
      :ok
    end

    test "uses short localized labels" do
      assert [%{type: :analog_input, label: "Analog Input"}] =
               ObjectTable.available_types([Enum.at(@objects, 0)])
    end
  end
end
