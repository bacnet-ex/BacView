defmodule BacViewWeb.ActiveAlarmsAssigns do
  @moduledoc false

  alias BacView.BACnet.ActiveAlarms

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    socket
    |> Phoenix.Component.assign(:alarm_popup_open, false)
    |> Phoenix.Component.assign(:active_alarm_entries, [])
  end

  @spec toggle(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def toggle(socket, opts \\ []) do
    open? = not socket.assigns.alarm_popup_open

    socket = Phoenix.Component.assign(socket, :alarm_popup_open, open?)

    if open?, do: refresh_now(socket, opts), else: socket
  end

  @spec close(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close(socket) do
    Phoenix.Component.assign(socket, :alarm_popup_open, false)
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
    entries = ActiveAlarms.list(list_opts(opts))
    Phoenix.Component.assign(socket, :active_alarm_entries, entries)
  end

  defp list_opts(opts) do
    opts
    |> Keyword.take([:device_id, :objects])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
