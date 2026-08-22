defmodule BacViewWeb.ReadPropertyHook do
  @moduledoc """
  LiveView `on_mount` hook that owns the global ReadProperty modal.
  """

  import Phoenix.LiveView

  alias BacViewWeb.ReadPropertyLive

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> ReadPropertyLive.init()
     |> attach_hook(:read_property_event, :handle_event, &handle_event/3)
     |> attach_hook(:read_property_async, :handle_async, &handle_async/3)}
  end

  defp handle_event("open_read_property", _params, socket) do
    {:halt, ReadPropertyLive.open(socket)}
  end

  defp handle_event("close_read_property", _params, socket) do
    {:halt, ReadPropertyLive.close(socket)}
  end

  defp handle_event("read_property_form_change", params, socket) do
    {:halt, ReadPropertyLive.change(socket, params)}
  end

  defp handle_event("read_property_execute", params, socket) do
    {:halt, ReadPropertyLive.execute(socket, params)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_async(:read_property, result, socket) do
    {:halt, ReadPropertyLive.apply_async(socket, result)}
  end

  defp handle_async(_name, _result, socket), do: {:cont, socket}
end
