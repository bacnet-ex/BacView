defmodule BacViewWeb.CovNotificationChartLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Protocol.CovNotificationChart
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.Protocol.TrendLogChart
  alias BacView.BACnet.Protocol.TrendLogExport

  @spec init_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init_assigns(socket) do
    socket
    |> assign(:cov_chart_modal_open, false)
    |> assign(:cov_chart_loading, false)
    |> assign(:cov_chart_error, nil)
    |> assign(:cov_chart_start, "")
    |> assign(:cov_chart_end, "")
    |> assign(:cov_chart_data, nil)
    |> assign(:cov_chart_has_data, false)
    |> assign(:cov_chart_record_count, 0)
    |> assign(:cov_chart_subscription, nil)
    |> assign(:cov_chart_object, nil)
  end

  @spec open_modal(Phoenix.LiveView.Socket.t(), map(), [map()]) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def open_modal(socket, params, objects) do
    with {:ok, type_atom} <- parse_type(params["type"]),
         instance_int <- String.to_integer(params["instance"]),
         {:ok, property} <- parse_property(params["property"] || "present_value") do
      object_id = %ObjectIdentifier{type: type_atom, instance: instance_int}

      subscription =
        Enum.find(socket.assigns.subscriptions, fn sub ->
          sub.object_id.type == type_atom and sub.object_id.instance == instance_int and
            sub.property == property
        end) || %{object_id: object_id, property: property}

      socket =
        socket
        |> assign(:cov_chart_modal_open, true)
        |> assign(:cov_chart_loading, true)
        |> assign(:cov_chart_error, nil)
        |> assign(:cov_chart_start, "")
        |> assign(:cov_chart_end, "")
        |> assign(:cov_chart_data, nil)
        |> assign(:cov_chart_has_data, false)
        |> assign(:cov_chart_record_count, 0)
        |> assign(:cov_chart_subscription, subscription)
        |> assign(:cov_chart_object, find_chart_object(objects, object_id))

      send(self(), :load_cov_chart)
      {:noreply, socket}
    else
      _err -> {:noreply, socket}
    end
  end

  @spec close_modal(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def close_modal(socket) do
    {:noreply,
     socket
     |> assign(:cov_chart_modal_open, false)
     |> assign(:cov_chart_loading, false)
     |> assign(:cov_chart_subscription, nil)
     |> assign(:cov_chart_object, nil)
     |> push_event("trend-chart:update", %{series: [], scales: [], empty_label: nil})}
  end

  @spec change_range(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def change_range(socket, params) do
    {:noreply,
     socket
     |> assign(:cov_chart_start, Map.get(params, "start", socket.assigns.cov_chart_start))
     |> assign(:cov_chart_end, Map.get(params, "end", socket.assigns.cov_chart_end))}
  end

  @spec load_chart(Phoenix.LiveView.Socket.t(), map()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def load_chart(socket, params) do
    socket =
      socket
      |> assign(:cov_chart_start, Map.get(params, "start", socket.assigns.cov_chart_start))
      |> assign(:cov_chart_end, Map.get(params, "end", socket.assigns.cov_chart_end))

    send(self(), :load_cov_chart)
    {:noreply, assign(socket, :cov_chart_loading, true)}
  end

  @spec download(Phoenix.LiveView.Socket.t(), :csv | :json) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def download(socket, format) do
    case socket.assigns.cov_chart_data do
      data when is_map(data) ->
        subscription = socket.assigns.cov_chart_subscription
        start_dt = parse_chart_datetime(socket.assigns.cov_chart_start)
        end_dt = parse_chart_datetime(socket.assigns.cov_chart_end)

        {content, mime, ext} =
          case format do
            :json ->
              {TrendLogExport.to_json(data,
                 object: %{
                   type: subscription.object_id.type,
                   instance: subscription.object_id.instance,
                   property: subscription.property
                 },
                 start_dt: start_dt,
                 end_dt: end_dt
               ), "application/json", "json"}

            _format ->
              {TrendLogExport.to_csv(data), "text/csv", "csv"}
          end

        filename =
          CovNotificationChart.filename(
            subscription.object_id.type,
            subscription.object_id.instance,
            subscription.property,
            start_dt,
            end_dt,
            ext
          )

        {:noreply,
         push_event(socket, "download_file", %{
           content: content,
           filename: filename,
           mime: mime
         })}

      _socket ->
        {:noreply, socket}
    end
  end

  @spec handle_load_info(Phoenix.LiveView.Socket.t(), [map()]) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_load_info(socket, objects) do
    if socket.assigns.cov_chart_modal_open and socket.assigns.cov_chart_subscription do
      parent = self()

      payload = %{
        device_id: socket.assigns.device_id,
        subscription: socket.assigns.cov_chart_subscription,
        notifications: socket.assigns.cov_notifications,
        objects: objects,
        start_value: socket.assigns.cov_chart_start,
        end_value: socket.assigns.cov_chart_end
      }

      Task.start(fn ->
        result = load_cov_chart_data(payload)
        send(parent, {:cov_chart_loaded, result})
      end)

      {:noreply, assign(socket, :cov_chart_loading, true)}
    else
      {:noreply, socket}
    end
  end

  @spec handle_loaded(Phoenix.LiveView.Socket.t(), term()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_loaded(socket, result) do
    socket = assign(socket, :cov_chart_loading, false)

    case result do
      {:ok,
       %{
         data: data,
         records: records,
         start_dt: start_dt,
         end_dt: end_dt
       }} ->
        {:noreply,
         socket
         |> assign(:cov_chart_data, data)
         |> assign(:cov_chart_start, TrendLogChart.to_form_value(start_dt))
         |> assign(:cov_chart_end, TrendLogChart.to_form_value(end_dt))
         |> assign(:cov_chart_has_data, chart_has_data?(data))
         |> assign(:cov_chart_record_count, length(records))
         |> assign(:cov_chart_error, nil)
         |> push_event("trend-chart:update", chart_event_payload(data))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:cov_chart_data, nil)
         |> assign(:cov_chart_has_data, false)
         |> assign(:cov_chart_record_count, 0)
         |> assign(:cov_chart_error, ErrorMessage.format_reason(reason))
         |> push_event("trend-chart:update", %{series: [], scales: [], empty_label: nil})}
    end
  end

  @spec maybe_reload_on_notification(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def maybe_reload_on_notification(socket) do
    if socket.assigns.cov_chart_modal_open do
      send(self(), :load_cov_chart)
      assign(socket, :cov_chart_loading, true)
    else
      socket
    end
  end

  defp load_cov_chart_data(%{
         device_id: device_id,
         subscription: subscription,
         notifications: notifications,
         objects: objects,
         start_value: start_value,
         end_value: end_value
       }) do
    with {:ok, filtered, start_dt, end_dt} <-
           select_cov_chart_notifications(notifications, subscription, start_value, end_value) do
      object = find_chart_object(objects, subscription.object_id)

      data =
        CovNotificationChart.build(filtered, subscription,
          device_id: device_id,
          object: object,
          start_dt: start_dt,
          end_dt: end_dt
        )

      {:ok, %{data: data, records: filtered, start_dt: start_dt, end_dt: end_dt}}
    end
  end

  defp select_cov_chart_notifications(notifications, subscription, start_value, end_value) do
    scoped =
      CovNotificationChart.notifications_for(
        notifications,
        subscription.object_id,
        subscription.property
      )

    if blank_chart_range?(start_value) and blank_chart_range?(end_value) do
      {start_dt, end_dt} = CovNotificationChart.range_from_notifications(scoped)
      {:ok, scoped, start_dt, end_dt}
    else
      with {:ok, start_dt} <- parse_chart_range(start_value, :start),
           {:ok, end_dt} <- parse_chart_range(end_value, :end),
           :ok <- validate_chart_range(start_dt, end_dt) do
        filtered =
          CovNotificationChart.filter_notifications_by_range(scoped, start_dt, end_dt)

        {:ok, filtered, start_dt, end_dt}
      end
    end
  end

  defp find_chart_object(objects, %{type: type, instance: instance}) when is_list(objects) do
    Enum.find(objects, &(&1.type == type and &1.instance == instance))
  end

  defp find_chart_object(_objects, _object_id), do: nil

  defp blank_chart_range?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_chart_range?(_value), do: true

  defp parse_chart_range(value, _fallback) when is_binary(value) do
    case TrendLogChart.parse_form_value(value) do
      {:ok, dt} -> {:ok, dt}
      :error -> {:error, :invalid_datetime_range}
    end
  end

  defp parse_chart_range(_value, _fallback), do: {:error, :invalid_datetime_range}

  defp parse_chart_datetime(value) when is_binary(value) do
    case TrendLogChart.parse_form_value(value) do
      {:ok, dt} -> dt
      :error -> nil
    end
  end

  defp parse_chart_datetime(_value), do: nil

  defp validate_chart_range(start_dt, end_dt) do
    if NaiveDateTime.compare(start_dt, end_dt) == :gt do
      {:error, :invalid_datetime_range}
    else
      :ok
    end
  end

  defp chart_has_data?(%{series: series}) when is_list(series) do
    Enum.any?(series, fn %{points: points} -> points != [] end)
  end

  defp chart_has_data?(_data), do: false

  defp chart_event_payload(%{series: series} = data) when is_list(series) do
    payload_series = BacViewWeb.ChartEventPayload.series_payload(series)

    if chart_has_data?(data) do
      Map.put(data, :series, payload_series)
    else
      %{
        series: [],
        scales: Map.get(data, :scales, []),
        markers: Map.get(data, :markers, []),
        range: Map.get(data, :range, %{}),
        empty_label: "Keine plottbaren COV-Meldungen im gewählten Zeitraum."
      }
    end
  end

  defp chart_event_payload(_data),
    do: %{series: [], scales: [], empty_label: "Keine Daten geladen."}

  defp parse_type(type) when is_binary(type) do
    {:ok, String.to_existing_atom(type)}
  rescue
    ArgumentError -> :error
  end

  defp parse_property("present_value"), do: {:ok, :present_value}
  defp parse_property(prop) when is_atom(prop), do: {:ok, prop}

  defp parse_property(prop) when is_binary(prop) do
    {:ok, String.to_existing_atom(prop)}
  rescue
    ArgumentError -> {:ok, prop}
  end
end
