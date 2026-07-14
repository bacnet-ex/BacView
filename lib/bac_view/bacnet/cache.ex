defmodule BacView.BACnet.Cache do
  @moduledoc """
  Owns named ETS tables for devices, objects, properties, and subscriptions.
  """
  use GenServer

  @tables [
    :bacview_devices,
    :bacview_objects,
    :bacview_properties,
    :bacview_subscriptions,
    :bacview_hierarchy,
    :bacview_name_hierarchy,
    :bacview_events,
    :bacview_validation_skip_modes
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the list of cache table names."
  @spec tables() :: [atom()]
  def tables(), do: @tables

  @impl true
  def init(_opts) do
    for table <- @tables do
      :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
    end

    {:ok, %{}}
  end
end
