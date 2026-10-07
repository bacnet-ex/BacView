defmodule BacViewWeb.PropertyExportHook do
  @moduledoc """
  LiveView `on_mount` hook that owns the global property export modal.
  """

  import Phoenix.LiveView

  alias BacViewWeb.PropertyExportLive

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> PropertyExportLive.init()
     |> attach_hook(:property_export_event, :handle_event, &handle_event/3)}
  end

  defp handle_event("open_property_export", _params, socket) do
    {:halt, PropertyExportLive.open(socket)}
  end

  defp handle_event("close_property_export", _params, socket) do
    {:halt, PropertyExportLive.close(socket)}
  end

  defp handle_event("validate_property_export", params, socket) do
    {:halt, PropertyExportLive.change(socket, params)}
  end

  defp handle_event("property_export_select_all_devices", _params, socket) do
    {:halt, PropertyExportLive.select_all_devices(socket)}
  end

  defp handle_event("property_export_select_no_devices", _params, socket) do
    {:halt, PropertyExportLive.select_no_devices(socket)}
  end

  defp handle_event("property_export_select_all_objects", _params, socket) do
    {:halt, PropertyExportLive.select_visible_objects(socket)}
  end

  defp handle_event("property_export_select_no_objects", _params, socket) do
    {:halt, PropertyExportLive.select_no_visible_objects(socket)}
  end

  defp handle_event("property_export_select_all_properties", _params, socket) do
    {:halt, PropertyExportLive.select_all_properties(socket)}
  end

  defp handle_event("property_export_select_no_properties", _params, socket) do
    {:halt, PropertyExportLive.select_no_properties(socket)}
  end

  defp handle_event("export_properties", params, socket) do
    {:halt, PropertyExportLive.export(socket, params)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
