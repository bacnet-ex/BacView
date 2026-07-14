defmodule BacViewWeb.DeviceBadgeCounts do
  @moduledoc false

  alias BacView.BACnet.ActiveAlarms
  alias BacView.BACnet.SubscriptionManager
  alias BacViewWeb.DeviceUrl

  @type t :: %{alarms: %{integer() => non_neg_integer()}, cov: %{integer() => non_neg_integer()}}

  @type cov_device_group :: %{
          device_id: non_neg_integer(),
          device_label: String.t(),
          device_description: String.t() | nil,
          count: non_neg_integer(),
          device_path: String.t()
        }

  @empty %{alarms: %{}, cov: %{}}

  @spec empty() :: t()
  def empty(), do: @empty

  @spec assign_counts(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_counts(socket) do
    device_ids = Enum.map(socket.assigns.devices, & &1.id)
    Phoenix.Component.assign(socket, :device_badge_counts, build(device_ids))
  end

  @spec build([integer()]) :: t()
  def build(device_ids) when is_list(device_ids) do
    %{
      alarms: alarm_counts(device_ids),
      cov: cov_counts()
    }
  end

  @spec alarm_count(t(), integer()) :: non_neg_integer()
  def alarm_count(%{alarms: counts}, device_id), do: Map.get(counts, device_id, 0)

  @spec cov_count(t(), integer()) :: non_neg_integer()
  def cov_count(%{cov: counts}, device_id), do: Map.get(counts, device_id, 0)

  @spec total_alarm_count(t()) :: non_neg_integer()
  def total_alarm_count(%{alarms: counts}) do
    counts
    |> Map.values()
    |> Enum.sum()
  end

  @spec total_cov_count(t()) :: non_neg_integer()
  def total_cov_count(%{cov: counts}) do
    counts
    |> Map.values()
    |> Enum.sum()
  end

  @spec cov_device_groups([map()], t()) :: [cov_device_group()]
  def cov_device_groups(devices, counts) when is_list(devices) do
    devices
    |> Enum.map(fn device ->
      count = cov_count(counts, device.id)

      if count > 0 do
        %{
          device_id: device.id,
          device_label: device_label(device),
          device_description: device_description(device),
          count: count,
          device_path: DeviceUrl.device_path(device.id, tab: "subscriptions")
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.device_label)
  end

  defp alarm_counts(device_ids) do
    device_ids
    |> Enum.map(fn device_id ->
      {device_id, length(ActiveAlarms.list(device_id: device_id))}
    end)
    |> Enum.reject(fn {_device_id, count} -> count == 0 end)
    |> Map.new()
  end

  defp cov_counts() do
    SubscriptionManager.list_active()
    |> Enum.group_by(& &1.device_id)
    |> Map.new(fn {device_id, subs} -> {device_id, length(subs)} end)
    |> Enum.reject(fn {_device_id, count} -> count == 0 end)
    |> Map.new()
  end

  defp device_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp device_label(%{instance: instance}), do: "Device #{instance}"
  defp device_label(_device), do: "Device"

  defp device_description(%{description: description})
       when is_binary(description) and description != "",
       do: description

  defp device_description(_device), do: nil
end
