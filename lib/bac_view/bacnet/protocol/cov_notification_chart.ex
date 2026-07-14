defmodule BacView.BACnet.Protocol.CovNotificationChart do
  @moduledoc false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.TrendLogChart
  alias BacView.BACnet.Protocol.TrendLogReader
  alias BacView.Timezone

  @trendable_types ~w(BOOLEAN INTEGER REAL)
  @trendable_bac_types ~w(boolean real unsigned_integer signed_integer double)a

  @spec trendable_subscription?(integer(), map()) :: boolean()
  def trendable_subscription?(device_id, %{object_id: object_id, property: property} = sub) do
    case find_property(device_id, object_id, property) do
      %{} = prop -> trendable_property?(prop)
      nil -> trendable_value?(Map.get(sub, :last_value))
    end
  end

  @spec trendable_property?(map()) :: boolean()
  def trendable_property?(prop) when is_map(prop) do
    cond do
      Map.get(prop, :bac_type) in @trendable_bac_types -> true
      Map.get(prop, :type) in @trendable_types -> true
      trendable_value?(Map.get(prop, :value)) -> true
      true -> false
    end
  end

  @spec notifications_for([map()], ObjectIdentifier.t(), atom() | integer()) :: [map()]
  def notifications_for(notifications, %ObjectIdentifier{} = object_id, property)
      when is_list(notifications) do
    Enum.filter(notifications, &matches_subscription?(&1, object_id, property))
  end

  @spec filter_notifications_by_range([map()], NaiveDateTime.t(), NaiveDateTime.t()) :: [map()]
  def filter_notifications_by_range(notifications, start_dt, end_dt)
      when is_list(notifications) do
    filter_by_range(notifications, start_dt, end_dt)
  end

  @spec range_from_notifications([map()]) :: {NaiveDateTime.t(), NaiveDateTime.t()}
  def range_from_notifications(notifications) when is_list(notifications) do
    notifications
    |> Enum.map(&received_naive/1)
    |> Enum.flat_map(fn
      %NaiveDateTime{} = naive -> [naive]
      _notifications -> []
    end)
    |> case do
      [] ->
        now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
        {now, now}

      timestamps ->
        sorted = Enum.sort(timestamps, NaiveDateTime)
        {List.first(sorted), List.last(sorted)}
    end
  end

  @spec build([map()], map(), keyword()) :: map()
  def build(notifications, %{object_id: object_id, property: property} = subscription, opts \\ [])
      when is_list(notifications) do
    start_dt = Keyword.get(opts, :start_dt)
    end_dt = Keyword.get(opts, :end_dt)
    device_id = Keyword.get(opts, :device_id)
    object = Keyword.get(opts, :object)

    filtered =
      notifications
      |> notifications_for(object_id, property)
      |> filter_by_range(start_dt, end_dt)

    points =
      filtered
      |> Enum.flat_map(&build_point(&1, object, property))
      |> Enum.sort_by(& &1.t)

    unit = series_unit(device_id, object_id, property, object, subscription)
    enum_chart? = MultistateState.enum_chart?(object, property)
    scale_id = if enum_chart?, do: "states", else: scale_id_for(unit)

    series = [
      maybe_put_series_paths(
        %{
          id: "s0",
          label: series_label(object_id, property, object),
          unit: unit,
          unit_label: unit_label(unit),
          scale_id: scale_id,
          points: points
        },
        enum_chart?
      )
    ]

    %{
      series: series,
      scales: build_scales(scale_id, unit, object, property),
      markers: [],
      range: %{
        start: start_dt && TrendLogChart.naive_to_unix_ms(start_dt),
        end: end_dt && TrendLogChart.naive_to_unix_ms(end_dt)
      }
    }
  end

  @spec filename(
          atom(),
          integer(),
          atom() | integer(),
          NaiveDateTime.t() | nil,
          NaiveDateTime.t() | nil,
          String.t()
        ) ::
          String.t()
  def filename(type, instance, property, start_dt, end_dt, ext \\ "csv") do
    prop = property |> to_string() |> String.replace("_", "-")
    start_part = filename_part(start_dt, "start")
    end_part = filename_part(end_dt, "end")
    "bacview-cov-#{type}-#{instance}-#{prop}-#{start_part}-#{end_part}.#{ext}"
  end

  defp matches_subscription?(
         %{object_id: %{type: type, instance: instance}, property: property},
         %ObjectIdentifier{type: type, instance: instance},
         property
       ),
       do: true

  defp matches_subscription?(_entry, _object_id, _property), do: false

  defp filter_by_range(notifications, nil, nil), do: notifications

  defp filter_by_range(notifications, start_dt, end_dt) do
    Enum.filter(notifications, fn entry ->
      case received_naive(entry) do
        %NaiveDateTime{} = naive ->
          NaiveDateTime.compare(naive, start_dt) != :lt and
            NaiveDateTime.compare(naive, end_dt) != :gt

        _notifications ->
          false
      end
    end)
  end

  defp received_naive(%{received_at: %DateTime{} = received_at}) do
    received_at
    |> Timezone.shift()
    |> DateTime.to_naive()
  end

  defp received_naive(_entry), do: nil

  defp received_at_to_ms(%DateTime{} = received_at) do
    case received_naive(%{received_at: received_at}) do
      %NaiveDateTime{} = naive -> {:ok, TrendLogChart.naive_to_unix_ms(naive)}
      _received_at -> :error
    end
  end

  defp received_at_to_ms(_received_at), do: :error

  defp find_property(device_id, %ObjectIdentifier{} = object_id, property) do
    if :ets.whereis(:bacview_properties) == :undefined do
      nil
    else
      device_id
      |> DeviceSession.get_properties(object_id)
      |> Enum.find(&(&1.property == property))
    end
  end

  defp trendable_value?(value) when is_number(value) or is_boolean(value), do: true
  defp trendable_value?(_value), do: false

  defp series_label(%ObjectIdentifier{type: type, instance: instance}, property, object) do
    prop =
      property
      |> to_string()
      |> String.replace("_", " ")

    base = "#{type}:#{instance} #{prop}"

    case object_description(object) do
      nil -> base
      description -> "#{description} (#{base})"
    end
  end

  defp object_description(%{description: description}) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_description(_object), do: nil

  defp series_unit(device_id, object_id, :present_value, object, _subscription) do
    case object do
      %{units: unit} when is_atom(unit) ->
        unit

      _object ->
        if device_id, do: object_units(device_id, object_id), else: nil
    end
  end

  defp series_unit(_device_id, _object_id, _property, _object, _subscription), do: nil

  defp object_units(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    Enum.find_value(DeviceSession.objects(device_id), fn obj ->
      if obj.type == type and obj.instance == instance, do: Map.get(obj, :units)
    end)
  end

  defp unit_label(nil), do: "—"
  defp unit_label(unit) when is_atom(unit), do: EngineeringUnits.symbol(unit)

  defp scale_id_for(nil), do: "raw"
  defp scale_id_for(unit) when is_atom(unit), do: Atom.to_string(unit)

  defp build_point(entry, object, property) do
    with {:ok, value} <- TrendLogReader.numeric_value(Map.get(entry, :value)),
         {:ok, ms} <- received_at_to_ms(Map.get(entry, :received_at)) do
      v = chart_value(value, object, property)
      point = %{t: ms, v: v}

      case chart_point_label(object, property, v) do
        nil -> [point]
        label -> [Map.put(point, :label, label)]
      end
    else
      _error -> []
    end
  end

  defp chart_value(value, object, property) do
    if MultistateState.enum_chart?(object, property), do: trunc(value), else: value
  end

  defp chart_point_label(object, property, value) do
    if MultistateState.enum_chart?(object, property) do
      MultistateState.format_present_value(value, object) || Integer.to_string(trunc(value))
    end
  end

  defp build_scales("states", _unit, object, property) do
    if MultistateState.enum_chart?(object, property) do
      [
        %{
          id: "states",
          label: "—",
          side: "left",
          kind: "enum",
          ticks: MultistateState.enum_ticks(object)
        }
      ]
    else
      build_scales("raw", nil, object, property)
    end
  end

  defp build_scales(scale_id, unit, _object, _property) do
    [
      %{
        id: scale_id,
        label: unit_label(unit),
        side: "left"
      }
    ]
  end

  defp maybe_put_series_paths(series, true), do: Map.put(series, :paths, "stepped")
  defp maybe_put_series_paths(series, _enum_chart?), do: series

  defp filename_part(%NaiveDateTime{} = dt, _fallback) do
    dt
    |> NaiveDateTime.to_string()
    |> String.replace([" ", ":"], "-")
  end

  defp filename_part(_fallback, fallback), do: fallback
end
