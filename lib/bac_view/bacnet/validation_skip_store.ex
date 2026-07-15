defmodule BacView.BACnet.ValidationSkipStore do
  @moduledoc """
  Owns property-validation skip modes chosen during scan recovery.

  Modes match the bacstack `skip_property_validation_remote_object` option:
  - `:value` - skip value validation only
  - `true` - skip type and value validation

  Resolution order for a read:
  1. Tagged object summaries on the live session (`state.objects`)
  2. Tagged summaries on `state.device.objects` (when present and distinct)
  3. ETS table `:bacview_validation_skip_modes` (survives session restarts)

  Full device rescan clears ETS entries for that device. Summary tags are not
  written on a clean scan; only successful recovery retries dual-write tags
  and ETS.
  """

  alias BACnet.Protocol.ObjectIdentifier

  @table :bacview_validation_skip_modes
  @modes [:value, true]

  @type mode :: :value | true

  @spec get(integer(), ObjectIdentifier.t()) :: mode() | nil
  def get(device_id, %ObjectIdentifier{} = object) when is_integer(device_id) do
    case lookup_ets(device_id, object) do
      mode when mode in @modes -> mode
      _other -> nil
    end
  end

  @spec put(integer(), ObjectIdentifier.t(), mode()) :: :ok
  def put(device_id, %ObjectIdentifier{} = object, mode)
      when is_integer(device_id) and mode in @modes do
    ensure_table!()
    :ets.insert(@table, {key(device_id, object), mode})
    :ok
  end

  @spec clear_device(integer()) :: :ok
  def clear_device(device_id) when is_integer(device_id) do
    if table_ready?() do
      match = {{device_id, :_, :_}, :_}

      :ets.select_delete(@table, [
        {match, [], [true]}
      ])
    end

    :ok
  end

  @spec from_objects([map()], ObjectIdentifier.t()) :: mode() | nil
  def from_objects(objects, %ObjectIdentifier{type: type, instance: instance})
      when is_list(objects) do
    Enum.find_value(objects, fn
      %{type: ^type, instance: ^instance} = obj ->
        case Map.get(obj, :property_validation_skip_mode) do
          mode when mode in @modes -> mode
          _other -> nil
        end

      _obj ->
        nil
    end)
  end

  def from_objects(_objects, _object), do: nil

  @spec apply_to_objects([map()], ObjectIdentifier.t(), mode()) :: [map()]
  def apply_to_objects(
        objects,
        %ObjectIdentifier{type: type, instance: instance},
        mode
      )
      when is_list(objects) and mode in @modes do
    Enum.map(objects, fn
      %{type: ^type, instance: ^instance} = obj ->
        Map.put(obj, :property_validation_skip_mode, mode)

      obj ->
        obj
    end)
  end

  @doc """
  Resolves skip mode from session-shaped sources.

  Accepts either a DeviceSession state map (`:objects`, `:device`, `:device_id`)
  or an explicit keyword list with `:objects`, `:device_objects`, `:device_id`.
  """
  @spec resolve(map() | keyword(), ObjectIdentifier.t()) :: mode() | nil
  def resolve(sources, %ObjectIdentifier{} = object) when is_list(sources) do
    objects = Keyword.get(sources, :objects, [])
    device_objects = Keyword.get(sources, :device_objects, [])
    device_id = Keyword.get(sources, :device_id)

    from_objects(objects, object) ||
      from_objects(device_objects, object) ||
      (is_integer(device_id) && get(device_id, object)) ||
      nil
  end

  def resolve(%{} = state, %ObjectIdentifier{} = object) do
    resolve(
      [
        objects: Map.get(state, :objects, []),
        device_objects: get_in(state, [:device, :objects]) || [],
        device_id: Map.get(state, :device_id)
      ],
      object
    )
  end

  defp lookup_ets(device_id, object) do
    if table_ready?() do
      case :ets.lookup(@table, key(device_id, object)) do
        [{_key, mode}] when mode in @modes -> mode
        _lookup -> nil
      end
    else
      nil
    end
  end

  defp key(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    {device_id, type, instance}
  end

  defp table_ready?(), do: :ets.whereis(@table) != :undefined

  # Normally created by BacView.BACnet.Cache. Defensive create keeps put/3 honest
  # under partial boot or isolated tests (never return :ok without a durable write).
  defp ensure_table!() do
    if table_ready?() do
      :ok
    else
      try do
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        :ok
      rescue
        ArgumentError ->
          if table_ready?() do
            :ok
          else
            reraise ArgumentError, "validation skip modes ETS table unavailable", __STACKTRACE__
          end
      end
    end
  end
end
