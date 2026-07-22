defmodule BacView.BACnet.Cache do
  @moduledoc """
  Owns named ETS tables for devices, objects, properties, and subscriptions.
  """
  use GenServer

  @tables [
    :bacview_devices,
    :bacview_device_share,
    :bacview_objects,
    :bacview_properties,
    :bacview_subscriptions,
    :bacview_hierarchy,
    :bacview_name_hierarchy,
    :bacview_events,
    :bacview_validation_skip_modes
  ]

  # Owned by SubscriptionManager / AlarmEvent / NotificationClassRecipient rather
  # than Cache.init/1, but still keyed by device and must go with a full clear.
  @extra_device_tables [
    :bacview_cov_notification_log,
    :bacview_cov_notification_seq,
    :bacview_notification_log,
    :bacview_notification_seq,
    :bacview_nc_recipients
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the list of cache table names."
  @spec tables() :: [atom()]
  def tables(), do: @tables

  @doc """
  Deletes every row from BACnet domain ETS tables (devices, objects, properties,
  subscriptions, events, skip modes, and related notification logs).

  Does not stop `DeviceSession` processes — call
  `DeviceSessionSupervisor.stop_all/0` first so sessions cannot re-populate
  caches while a clear is in progress.
  """
  @spec clear_all_device_data() :: :ok
  def clear_all_device_data() do
    for table <- @tables ++ @extra_device_tables do
      if :ets.whereis(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end

    :ok
  end

  @impl true
  def init(_opts) do
    for table <- @tables do
      :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
    end

    {:ok, %{}}
  end
end
