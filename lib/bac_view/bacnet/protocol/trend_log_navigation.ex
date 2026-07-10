defmodule BacView.BACnet.Protocol.TrendLogNavigation do
  @moduledoc false

  alias BACnet.Protocol.DeviceObjectPropertyRef
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.TrendLogChart
  alias BacView.BACnet.Protocol.TrendLogReader
  alias BacViewWeb.DeviceUrl

  @type target :: %{
          type: atom(),
          instance: non_neg_integer(),
          name: String.t() | nil,
          label: String.t(),
          href: String.t()
        }

  @spec targets_for_object(
          integer(),
          map(),
          [map()],
          [map()],
          non_neg_integer() | nil,
          keyword()
        ) :: [target()]
  def targets_for_object(
        device_id,
        object,
        device_objects,
        properties,
        device_instance,
        url_opts \\ []
      )
      when is_map(object) do
    if TrendLogReader.trend_log_type?(object.type) do
      referenced_object_targets(properties, device_objects, device_instance, url_opts)
    else
      referencing_trend_log_targets(device_id, object, device_objects, device_instance, url_opts)
    end
  end

  @doc false
  @spec log_property_refs(integer(), map()) :: [DeviceObjectPropertyRef.t()]
  def log_property_refs(device_id, %{type: type, instance: instance} = object)
      when type in [:trend_log, :trend_log_multiple] do
    case Map.get(object, :log_property_refs) do
      refs when is_list(refs) ->
        refs

      _object ->
        object_id = %ObjectIdentifier{type: type, instance: instance}
        props = DeviceSession.get_properties(device_id, object_id)
        TrendLogChart.property_refs_from_properties(props)
    end
  end

  def log_property_refs(_device_id, _object), do: []

  @doc false
  @spec log_property_refs_from_value(term()) :: [DeviceObjectPropertyRef.t()]
  def log_property_refs_from_value(value) do
    TrendLogChart.property_refs_from_properties([
      %{property: :log_device_object_property, value: value}
    ])
  end

  defp referenced_object_targets(properties, device_objects, device_instance, url_opts) do
    properties
    |> TrendLogChart.property_refs_from_properties()
    |> Enum.filter(&same_device_ref?(&1, device_instance))
    |> Enum.map(&ref_object_target(&1, device_objects, url_opts))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.type, &1.instance})
  end

  defp referencing_trend_log_targets(
         device_id,
         %{type: type, instance: instance} = object,
         device_objects,
         device_instance,
         url_opts
       ) do
    device_objects
    |> Enum.filter(fn trend_log ->
      TrendLogReader.trend_log_type?(trend_log.type) and
        not same_object?(trend_log, type, instance) and
        references_object?(log_property_refs(device_id, trend_log), object, device_instance)
    end)
    |> Enum.map(&trend_log_target(&1, url_opts))
  end

  defp references_object?(
         refs,
         %{type: type, instance: instance},
         device_instance
       )
       when is_list(refs) do
    Enum.any?(refs, fn ref ->
      same_device_ref?(ref, device_instance) and
        ref.object_identifier.type == type and ref.object_identifier.instance == instance
    end)
  end

  defp references_object?(_refs, _object, _device_instance), do: false

  defp same_device_ref?(%DeviceObjectPropertyRef{device_identifier: nil}, _device_instance),
    do: true

  defp same_device_ref?(
         %DeviceObjectPropertyRef{
           device_identifier: %ObjectIdentifier{type: :device, instance: instance}
         },
         device_instance
       )
       when is_integer(device_instance),
       do: instance == device_instance

  defp same_device_ref?(_ref, _device_instance), do: false

  defp ref_object_target(%DeviceObjectPropertyRef{} = ref, device_objects, url_opts) do
    %{type: type, instance: instance} = ref.object_identifier

    case find_device_object(device_objects, type, instance) do
      nil ->
        nil

      obj ->
        build_target(obj, url_opts)
    end
  end

  defp trend_log_target(trend_log, url_opts), do: build_target(trend_log, url_opts)

  defp build_target(%{type: type, instance: instance} = obj, url_opts) do
    name = object_name(obj)

    %{
      type: type,
      instance: instance,
      name: name,
      label: target_label(obj),
      href: object_href(url_opts, type, instance)
    }
  end

  defp target_label(%{name: name, type: type, instance: instance})
       when is_binary(name) and name != "" do
    "#{name} (#{type}:#{instance})"
  end

  defp target_label(%{type: type, instance: instance}) do
    type_label = ObjectTypes.short_label(type)
    "#{type_label} #{instance}"
  end

  defp object_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp object_name(_obj), do: nil

  defp object_href(url_opts, type, instance) do
    device_id = Keyword.fetch!(url_opts, :device_id)

    DeviceUrl.object_path(device_id, type, instance,
      tab: Keyword.get(url_opts, :tab, "hierarchy"),
      search: Keyword.get(url_opts, :search, ""),
      types: Keyword.get(url_opts, :types, []),
      status: Keyword.get(url_opts, :status, []),
      sort: Keyword.get(url_opts, :sort),
      dir: Keyword.get(url_opts, :dir),
      alarm_view: Keyword.get(url_opts, :alarm_view),
      cov_view: Keyword.get(url_opts, :cov_view),
      hierarchy_view: Keyword.get(url_opts, :hierarchy_view),
      hierarchy_path: Keyword.get(url_opts, :hierarchy_path, [])
    )
  end

  defp find_device_object(objects, type, instance) when is_list(objects) do
    Enum.find(objects, &(&1.type == type and &1.instance == instance))
  end

  defp same_object?(%{type: obj_type, instance: obj_instance}, type, instance) do
    obj_type == type and obj_instance == instance
  end
end
