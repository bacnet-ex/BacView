defmodule BacViewWeb.DeviceServicesHandlers do
  @moduledoc false

  alias BacView.BACnet.DeviceServices
  alias BacViewWeb.LiveFlash

  @device_service_events ~w(
    toggle_device_services_menu
    close_device_services_menu
    open_device_service_modal
    close_device_service_modal
    device_service_form_change
    execute_device_service
  )

  @spec device_service_events() :: [String.t()]
  def device_service_events(), do: @device_service_events

  @spec init_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init_assigns(socket) do
    socket
    |> Phoenix.Component.assign(:device_service_menu, nil)
    |> Phoenix.Component.assign(:device_service_modal, nil)
    |> Phoenix.Component.assign(:device_service_busy, false)
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()} | :not_handled
  def handle_event("toggle_device_services_menu", params, socket) do
    device_id = device_id_from_params!(params)

    menu =
      case socket.assigns.device_service_menu do
        %{device_id: ^device_id} -> nil
        _handle_event -> %{device_id: device_id}
      end

    {:noreply,
     socket
     |> Phoenix.Component.assign(:device_service_menu, menu)
     |> Phoenix.Component.assign(:device_service_modal, nil)}
  end

  def handle_event("close_device_services_menu", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :device_service_menu, nil)}
  end

  def handle_event("open_device_service_modal", params, socket) do
    service = Map.fetch!(params, "service")
    device_id = device_id_from_params!(params)
    modal = build_modal(service, device_id)

    {:noreply,
     socket
     |> Phoenix.Component.assign(:device_service_menu, nil)
     |> Phoenix.Component.assign(:device_service_modal, modal)}
  end

  def handle_event("close_device_service_modal", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :device_service_modal, nil)}
  end

  def handle_event("device_service_form_change", %{"service" => params}, socket) do
    case socket.assigns.device_service_modal do
      %{form: form} = modal ->
        merged =
          form
          |> Map.merge(params)
          |> Map.drop(["_target"])

        {:noreply,
         Phoenix.Component.assign(socket, :device_service_modal, %{modal | form: merged})}

      _handle_event ->
        {:noreply, socket}
    end
  end

  def handle_event("execute_device_service", _params, socket) do
    case socket.assigns.device_service_modal do
      %{type: type, device_id: device_id, form: form} = modal ->
        socket = Phoenix.Component.assign(socket, :device_service_busy, true)
        parent = self()

        Task.start(fn ->
          result = execute_service(type, device_id, form)
          send(parent, {:device_service_complete, modal, result})
        end)

        {:noreply, socket}

      _handle_event ->
        {:noreply, socket}
    end
  end

  def handle_event(_event, _params, _socket), do: :not_handled

  @spec handle_info({:device_service_complete, map(), term()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()} | :not_handled
  def handle_info({:device_service_complete, modal, result}, socket) do
    action = service_action(modal.type)

    socket =
      socket
      |> Phoenix.Component.assign(:device_service_busy, false)
      |> Phoenix.Component.assign(:device_service_modal, nil)
      |> Phoenix.Component.assign(:device_service_menu, nil)

    socket =
      case result do
        :ok ->
          Phoenix.LiveView.put_flash(socket, :info, success_message(modal.type))

        {:error, reason} ->
          LiveFlash.put_error(socket, action, reason)
      end

    {:noreply, socket}
  end

  def handle_info(_msg, _socket), do: :not_handled

  defp build_modal("dcc", device_id) do
    %{type: :dcc, device_id: device_id, form: DeviceServices.default_dcc_form()}
  end

  defp build_modal("reinitialize", device_id) do
    %{
      type: :reinitialize,
      device_id: device_id,
      form: DeviceServices.default_reinitialize_form()
    }
  end

  defp build_modal("time_sync", device_id) do
    %{type: :time_sync, device_id: device_id, form: DeviceServices.default_time_sync_form()}
  end

  defp build_modal(_build_modal, device_id) do
    %{type: :time_sync, device_id: device_id, form: DeviceServices.default_time_sync_form()}
  end

  defp execute_service(:dcc, device_id, form),
    do: DeviceServices.device_communication_control(device_id, form)

  defp execute_service(:reinitialize, device_id, form),
    do: DeviceServices.reinitialize_device(device_id, form)

  defp execute_service(:time_sync, device_id, form),
    do: DeviceServices.send_time_synchronization(device_id, form)

  defp service_action(:dcc), do: :device_communication_control
  defp service_action(:reinitialize), do: :reinitialize_device
  defp service_action(:time_sync), do: :time_synchronization
  defp service_action(_dcc), do: :generic

  defp success_message(:dcc),
    do: BacViewWeb.GettextBackend.gt("Gerätekommunikation wurde gesteuert.")

  defp success_message(:reinitialize),
    do: BacViewWeb.GettextBackend.gt("Gerät wird neu initialisiert.")

  defp success_message(:time_sync),
    do: BacViewWeb.GettextBackend.gt("Zeitsynchronisation gesendet.")

  defp success_message(_dcc), do: BacViewWeb.GettextBackend.gt("Dienst ausgeführt.")

  defp device_id_from_params!(params) do
    id =
      Map.get(params, "device_id") ||
        Map.get(params, "device-id") ||
        raise ArgumentError, "missing device_id in #{inspect(params)}"

    normalize_device_id!(id)
  end

  defp normalize_device_id!(id) when is_integer(id), do: id

  defp normalize_device_id!(id) when is_binary(id), do: String.to_integer(id)
end
