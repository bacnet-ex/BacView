defmodule BacViewWeb.ActiveCovSubscriptionsAssigns do
  @moduledoc false

  alias BacViewWeb.ActiveCovSubscriptions
  alias BacViewWeb.DeviceBadgeCounts

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    socket
    |> Phoenix.Component.assign(:cov_popup_open, false)
    |> Phoenix.Component.assign(:cov_popup_grouped?, false)
    |> Phoenix.Component.assign(:active_cov_entries, [])
    |> Phoenix.Component.assign(:active_cov_device_groups, [])
  end

  @spec toggle(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def toggle(socket, opts \\ []) do
    open? = not socket.assigns.cov_popup_open
    grouped? = grouped?(opts)

    socket =
      socket
      |> Phoenix.Component.assign(:cov_popup_open, open?)
      |> Phoenix.Component.assign(:cov_popup_grouped?, grouped?)

    if open?, do: refresh_now(socket, opts), else: socket
  end

  @spec close(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close(socket) do
    Phoenix.Component.assign(socket, :cov_popup_open, false)
  end

  @spec refresh(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def refresh(socket, opts \\ []) do
    if socket.assigns.cov_popup_open do
      refresh_now(socket, opts)
    else
      socket
    end
  end

  defp refresh_now(socket, opts) do
    case Keyword.get(opts, :grouped_devices) do
      devices when is_list(devices) ->
        counts = grouped_counts(socket, opts)

        Phoenix.Component.assign(
          socket,
          :active_cov_device_groups,
          DeviceBadgeCounts.cov_device_groups(devices, counts)
        )

      _flat ->
        entries =
          ActiveCovSubscriptions.list(
            device_id: socket.assigns.device_id,
            subscriptions: socket.assigns.subscriptions,
            objects: popup_objects(socket.assigns),
            list_opts: list_opts(socket, opts)
          )

        Phoenix.Component.assign(socket, :active_cov_entries, entries)
    end
  end

  defp grouped?(opts), do: is_list(Keyword.get(opts, :grouped_devices))

  defp grouped_counts(socket, opts) do
    Keyword.get(opts, :device_badge_counts, socket.assigns.device_badge_counts)
  end

  defp popup_objects(assigns) do
    Map.get(assigns, :device_objects, Map.get(assigns, :objects, []))
  end

  defp list_opts(socket, opts) do
    opts
    |> Keyword.get(:list_opts)
    |> case do
      nil -> list_opts_from_assigns(socket.assigns)
      list_opts -> list_opts
    end
  end

  defp list_opts_from_assigns(%{return_tab: _return_tab} = assigns) do
    [
      tab: assigns.return_tab,
      search: assigns.objects_search,
      types: assigns.objects_type_filter,
      status: assigns.objects_status_filter,
      sort: assigns.objects_sort_by,
      dir: assigns.objects_sort_dir,
      alarm_view: assigns.return_alarm_view,
      cov_view: assigns.return_cov_view,
      hierarchy_view: assigns.return_hierarchy_view,
      hierarchy_path: assigns.return_hierarchy_path,
      h_split: BacView.BACnet.HierarchySplit.encode(assigns.return_hierarchy_split),
      device_id: assigns.device_id
    ]
  end

  defp list_opts_from_assigns(assigns) do
    [
      tab: assigns.tab,
      search: assigns.search,
      types: assigns.type_filter,
      status: assigns.status_filter,
      sort: assigns.sort_by,
      dir: assigns.sort_dir,
      alarm_view: assigns.alarm_view,
      cov_view: assigns.cov_view,
      hierarchy_view: assigns.hierarchy_view,
      hierarchy_path: assigns.hierarchy_path,
      h_split: BacView.BACnet.HierarchySplit.encode(assigns.hierarchy_split),
      device_id: assigns.device_id
    ]
  end
end
