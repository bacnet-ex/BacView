defmodule BacViewWeb.ActiveAlarmsAssigns do
  @moduledoc false

  alias BacView.BACnet.ActiveAlarms

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    socket
    |> Phoenix.Component.assign(:alarm_popup_open, false)
    |> Phoenix.Component.assign(:alarm_popup_grouped?, false)
    |> Phoenix.Component.assign(:alarm_popup_level, :devices)
    |> Phoenix.Component.assign(:alarm_popup_device_id, nil)
    |> Phoenix.Component.assign(:active_alarm_device_groups, [])
    |> Phoenix.Component.assign(:active_alarm_entries, [])
  end

  @spec toggle(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def toggle(socket, opts \\ []) do
    open? = not socket.assigns.alarm_popup_open
    grouped? = grouped?(opts)

    socket =
      socket
      |> Phoenix.Component.assign(:alarm_popup_open, open?)
      |> Phoenix.Component.assign(:alarm_popup_grouped?, grouped?)

    cond do
      open? ->
        refresh_now(socket, opts)

      grouped? ->
        reset_grouped(socket)

      true ->
        socket
    end
  end

  @spec close(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close(socket) do
    socket
    |> Phoenix.Component.assign(:alarm_popup_open, false)
    |> reset_grouped()
  end

  @spec select_device(Phoenix.LiveView.Socket.t(), integer(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def select_device(socket, device_id, opts \\ []) do
    socket
    |> Phoenix.Component.assign(:alarm_popup_level, :entries)
    |> Phoenix.Component.assign(:alarm_popup_device_id, device_id)
    |> refresh_now(opts)
  end

  @spec back_to_devices(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def back_to_devices(socket, opts \\ []) do
    socket
    |> Phoenix.Component.assign(:alarm_popup_level, :devices)
    |> Phoenix.Component.assign(:alarm_popup_device_id, nil)
    |> refresh_now(opts)
  end

  @spec refresh(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def refresh(socket, opts \\ []) do
    if socket.assigns.alarm_popup_open do
      refresh_now(socket, opts)
    else
      socket
    end
  end

  defp refresh_now(socket, opts) do
    case Keyword.get(opts, :grouped_device_ids) do
      device_ids when is_list(device_ids) ->
        refresh_grouped(socket, device_ids, opts)

      _flat ->
        entries = ActiveAlarms.list(list_opts(opts))
        Phoenix.Component.assign(socket, :active_alarm_entries, entries)
    end
  end

  defp refresh_grouped(socket, device_ids, opts) do
    case socket.assigns.alarm_popup_level do
      :devices ->
        socket
        |> Phoenix.Component.assign(
          :active_alarm_device_groups,
          ActiveAlarms.device_groups(device_ids)
        )
        |> Phoenix.Component.assign(:active_alarm_entries, [])

      :entries ->
        device_id = socket.assigns.alarm_popup_device_id

        entries =
          [device_id: device_id]
          |> maybe_add_objects(opts)
          |> ActiveAlarms.list()

        Phoenix.Component.assign(socket, :active_alarm_entries, entries)
    end
  end

  defp reset_grouped(socket) do
    socket
    |> Phoenix.Component.assign(:alarm_popup_level, :devices)
    |> Phoenix.Component.assign(:alarm_popup_device_id, nil)
    |> Phoenix.Component.assign(:active_alarm_device_groups, [])
    |> Phoenix.Component.assign(:active_alarm_entries, [])
  end

  defp grouped?(opts), do: is_list(Keyword.get(opts, :grouped_device_ids))

  defp list_opts(opts) do
    opts
    |> Keyword.take([:device_id, :objects])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_add_objects(list_opts, opts) do
    case Keyword.get(opts, :objects) do
      nil -> list_opts
      objects -> Keyword.put(list_opts, :objects, objects)
    end
  end
end
