defmodule BacView.BACnet.NameHierarchyCache do
  @moduledoc """
  Caches name-based hierarchy split rules per device until the object structure
  changes significantly (objects added or removed).
  """

  @table :bacview_name_hierarchy

  @type entry :: %{
          split: BacView.BACnet.HierarchySplit.t(),
          fingerprint: term()
        }

  @spec put(integer(), BacView.BACnet.HierarchySplit.t(), [map()]) :: :ok
  def put(device_id, split, objects) when is_integer(device_id) do
    :ets.insert(
      ensure_table(),
      {device_id, %{split: split, fingerprint: structure_fingerprint(objects)}}
    )

    :ok
  end

  @spec get(integer()) :: entry() | nil
  def get(device_id) when is_integer(device_id) do
    case :ets.lookup(ensure_table(), device_id) do
      [{^device_id, entry}] -> entry
      [] -> nil
    end
  end

  @spec clear(integer()) :: :ok
  def clear(device_id) when is_integer(device_id) do
    :ets.delete(ensure_table(), device_id)
    :ok
  end

  @doc """
  Resolves the active split for a device.

  An explicit URL split takes precedence and refreshes the cache. When the URL
  omits a split, a cached split is restored if the current object structure
  still matches the cached fingerprint.
  """
  @spec resolve(integer(), BacView.BACnet.HierarchySplit.t() | nil, [map()]) ::
          BacView.BACnet.HierarchySplit.t() | nil
  def resolve(device_id, url_split, objects)
      when is_integer(device_id) and is_list(objects) do
    case url_split do
      split when not is_nil(split) ->
        if objects != [], do: put(device_id, split, objects)
        split

      nil ->
        restore_cached(device_id, objects)
    end
  end

  @spec structure_fingerprint([map()]) :: [{atom(), non_neg_integer()}]
  def structure_fingerprint(objects) when is_list(objects) do
    objects
    |> Enum.reject(&(&1.type == :structured_view))
    |> Enum.map(fn obj -> {obj.type, obj.instance} end)
    |> Enum.sort()
  end

  defp ensure_table() do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

      table ->
        table
    end
  end

  defp restore_cached(device_id, objects) do
    case get(device_id) do
      nil ->
        nil

      %{split: split, fingerprint: fingerprint} ->
        if objects == [] or structure_fingerprint(objects) == fingerprint do
          split
        else
          clear(device_id)
          nil
        end
    end
  end
end
