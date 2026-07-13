defmodule BacView.BACnet.NameHierarchyCacheTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.NameHierarchyCache
  alias BacView.Test.BacnetEtsLock

  @table :bacview_name_hierarchy
  @table_opts [:named_table, :set, :public, read_concurrency: true]

  defp sample_objects do
    [
      %{type: :analog_input, instance: 1, name: "Floor1.RoomA.Temp"},
      %{type: :analog_input, instance: 2, name: "Floor1.RoomB.Temp"},
      %{type: :structured_view, instance: 10, name: "SV"}
    ]
  end

  setup do
    BacnetEtsLock.reset_tables!([{@table, @table_opts}])
    :ok
  end

  test "put and get store split with structure fingerprint" do
    split = {:delimiter, "_"}
    objects = sample_objects()

    :ok = NameHierarchyCache.put(42, split, objects)

    assert %{split: ^split, fingerprint: fingerprint} = NameHierarchyCache.get(42)
    assert fingerprint == NameHierarchyCache.structure_fingerprint(objects)
  end

  test "resolve prefers explicit url split and refreshes cache" do
    old_split = {:delimiter, "_"}
    new_split = {:delimiter, "."}
    objects = sample_objects()

    NameHierarchyCache.put(7, old_split, objects)

    assert NameHierarchyCache.resolve(7, new_split, objects) == new_split
    assert NameHierarchyCache.get(7).split == new_split
  end

  test "resolve restores cached split when url omits it" do
    split = {:positions, [5, 3]}
    objects = sample_objects()

    NameHierarchyCache.put(3, split, objects)

    assert NameHierarchyCache.resolve(3, nil, objects) == split
  end

  test "resolve returns nil when structure changed significantly" do
    split = {:delimiter, "-"}
    objects = sample_objects()
    changed = [%{type: :analog_input, instance: 99, name: "New"}]

    NameHierarchyCache.put(5, split, objects)

    assert NameHierarchyCache.resolve(5, nil, changed) == nil
    assert NameHierarchyCache.get(5) == nil
  end

  test "resolve restores cached split before objects are loaded" do
    split = {:delimiter, " "}
    objects = sample_objects()

    NameHierarchyCache.put(9, split, objects)

    assert NameHierarchyCache.resolve(9, nil, []) == split
    assert NameHierarchyCache.get(9).split == split
  end

  test "clear removes cached split" do
    NameHierarchyCache.put(11, {:delimiter, "/"}, sample_objects())
    :ok = NameHierarchyCache.clear(11)

    assert NameHierarchyCache.get(11) == nil
    assert NameHierarchyCache.resolve(11, nil, sample_objects()) == nil
  end

  test "structure fingerprint ignores structured views and object names" do
    objects = sample_objects()
    renamed = Enum.map(objects, fn obj -> Map.put(obj, :name, "renamed") end)

    assert NameHierarchyCache.structure_fingerprint(objects) ==
             NameHierarchyCache.structure_fingerprint(renamed)
  end
end
