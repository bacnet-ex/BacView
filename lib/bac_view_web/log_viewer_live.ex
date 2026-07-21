defmodule BacViewWeb.LogViewerLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias BacView.LogStore

  @doc "Initial log-viewer assigns for a LiveView mount."
  def init(socket) do
    socket
    |> assign(:log_viewer_open, false)
    |> assign(:log_viewer_entries, [])
    |> assign(:log_viewer_level, "debug")
    |> assign(:log_path, LogStore.path())
  end

  def open(socket) do
    if connected?(socket), do: LogStore.subscribe()

    socket
    |> assign(:log_viewer_open, true)
    |> assign(:log_path, LogStore.path())
    |> refresh_entries()
  end

  def close(socket), do: assign(socket, :log_viewer_open, false)

  def refresh(socket), do: refresh_entries(socket)

  def clear(socket) do
    LogStore.clear()
    assign(socket, :log_viewer_entries, [])
  end

  def filter(socket, level) when is_binary(level) do
    socket
    |> assign(:log_viewer_level, level)
    |> refresh_entries()
  end

  def append_entry(socket, entry) do
    if socket.assigns.log_viewer_open and
         level_passes?(entry.level, socket.assigns.log_viewer_level) do
      entries =
        [entry | Enum.reverse(socket.assigns.log_viewer_entries)]
        |> Enum.take(500)
        |> Enum.reverse()

      assign(socket, :log_viewer_entries, entries)
    else
      socket
    end
  end

  defp refresh_entries(socket) do
    level =
      case socket.assigns.log_viewer_level do
        level when level in ~w(debug info warning error) -> String.to_existing_atom(level)
        _other -> :debug
      end

    assign(socket, :log_viewer_entries, LogStore.list(level: level, limit: 500))
  end

  defp level_passes?(entry_level, filter) when is_binary(filter) do
    case filter do
      level when level in ~w(debug info warning error) ->
        Logger.compare_levels(entry_level, String.to_existing_atom(level)) != :lt

      _other ->
        true
    end
  end
end
