defmodule BacViewWeb.MultiEdeExportHook do
  @moduledoc """
  LiveView `on_mount` hook that owns the global multi-device EDE export modal.
  """

  import Phoenix.LiveView

  alias BacViewWeb.MultiEdeExportLive

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> MultiEdeExportLive.init()
     |> attach_hook(:multi_ede_export_event, :handle_event, &handle_event/3)}
  end

  defp handle_event("open_multi_ede_export", _params, socket) do
    {:halt, MultiEdeExportLive.open(socket)}
  end

  defp handle_event("close_multi_ede_export", _params, socket) do
    {:halt, MultiEdeExportLive.close(socket)}
  end

  defp handle_event("validate_multi_ede_export", params, socket) do
    {:halt, MultiEdeExportLive.change(socket, params)}
  end

  defp handle_event("multi_ede_export_select_all_types", _params, socket) do
    {:halt, MultiEdeExportLive.select_all_types(socket)}
  end

  defp handle_event("multi_ede_export_select_default_types", _params, socket) do
    {:halt, MultiEdeExportLive.select_default_types(socket)}
  end

  defp handle_event("multi_ede_export_select_all_devices", _params, socket) do
    {:halt, MultiEdeExportLive.select_all_devices(socket)}
  end

  defp handle_event("multi_ede_export_select_no_devices", _params, socket) do
    {:halt, MultiEdeExportLive.select_no_devices(socket)}
  end

  defp handle_event("export_multi_ede", params, socket) do
    {:halt, MultiEdeExportLive.export(socket, params)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
