defmodule BacViewWeb.ActiveCovSubscriptions do
  @moduledoc false

  alias BacView.BACnet.Protocol.CovNotificationChart
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.SubscriptionTable

  @type entry :: %{
          id: String.t(),
          object_label: String.t(),
          object_name: String.t() | nil,
          description: String.t() | nil,
          property_label: String.t(),
          value_label: String.t(),
          type: atom(),
          instance: non_neg_integer(),
          property: atom() | integer(),
          chartable?: boolean(),
          object_path: String.t()
        }

  @spec list(keyword()) :: [entry()]
  def list(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    subscriptions = Keyword.get(opts, :subscriptions, [])
    objects = Keyword.get(opts, :objects, [])
    list_opts = Keyword.get(opts, :list_opts, [])

    subscriptions
    |> SubscriptionTable.enrich_subscriptions(objects)
    |> Enum.sort_by(&{&1.object_id.type, &1.object_id.instance, &1.property}, :asc)
    |> Enum.map(&build_entry(&1, device_id, list_opts))
  end

  defp build_entry(sub, device_id, list_opts) do
    object_id = sub.object_id

    %{
      id: "#{device_id}-#{object_id.type}-#{object_id.instance}-#{sub.property}",
      object_label: "#{object_id.type}:#{object_id.instance}",
      object_name: Map.get(sub, :object_name),
      description: Map.get(sub, :description),
      property_label: to_string(sub.property),
      value_label: sub.last_value_formatted || "-",
      type: object_id.type,
      instance: object_id.instance,
      property: sub.property,
      chartable?: CovNotificationChart.trendable_subscription?(device_id, sub),
      object_path: object_path(device_id, object_id, list_opts)
    }
  end

  defp object_path(device_id, %{type: type, instance: instance}, list_opts) do
    url_opts =
      list_opts
      |> Keyword.delete(:device_id)
      |> Keyword.put(:tab, "subscriptions")

    DeviceUrl.object_path(device_id, type, instance, url_opts)
  end
end
