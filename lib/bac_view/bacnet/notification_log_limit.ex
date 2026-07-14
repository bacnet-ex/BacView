defmodule BacView.BACnet.NotificationLogLimit do
  @moduledoc false

  @max_device_entries 1000
  @max_cov_subscription_entries 1000
  @max_cov_device_entries 50_000

  @type subscription_key :: {integer(), atom(), non_neg_integer(), atom() | integer()}

  @spec max_entries() :: pos_integer()
  def max_entries(), do: @max_device_entries

  @spec max_cov_subscription_entries() :: pos_integer()
  def max_cov_subscription_entries(), do: @max_cov_subscription_entries

  @spec max_cov_device_entries() :: pos_integer()
  def max_cov_device_entries(), do: @max_cov_device_entries

  @spec prune_device(:ets.tid() | atom(), integer()) :: :ok
  def prune_device(table, device_id) when is_integer(device_id) do
    prune_by_match(
      table,
      {{device_id, :_, :_}, :_},
      @max_device_entries,
      &device_sort_key/1
    )
  end

  @spec prune_cov_subscription(:ets.tid() | atom(), subscription_key()) :: :ok
  def prune_cov_subscription(table, {device_id, type, instance, property}) do
    prune_by_match(
      table,
      {{device_id, type, instance, property, :_, :_}, :_},
      @max_cov_subscription_entries,
      &cov_sort_key/1
    )
  end

  @spec prune_cov_device(:ets.tid() | atom(), integer()) :: :ok
  def prune_cov_device(table, device_id) when is_integer(device_id) do
    prune_by_match(
      table,
      {{device_id, :_, :_, :_, :_, :_}, :_},
      @max_cov_device_entries,
      &cov_sort_key/1
    )
  end

  defp prune_by_match(table, match, max_entries, sort_key_fun) do
    entries = :ets.match_object(table, match)
    drop = length(entries) - max_entries

    if drop > 0 do
      entries
      |> Enum.sort_by(sort_key_fun, :desc)
      |> Enum.take(drop)
      |> Enum.each(&:ets.delete_object(table, &1))
    end

    :ok
  end

  defp device_sort_key({{_device_id, neg_micro, seq}, _entry}), do: {neg_micro, seq}

  defp cov_sort_key({{_device_id, _type, _instance, _property, neg_micro, seq}, _entry}),
    do: {neg_micro, seq}
end
