defmodule BacViewWeb.BulkWritePropertyLive do
  @moduledoc false

  import BacViewWeb.GettextBackend, only: [gt: 1]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias BacView.BACnet.BulkPropertyWrite
  alias BacView.BACnet.PropertyExport
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacViewWeb.WriteFormParams

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("open_bulk_write_property", _params, socket) do
    {:noreply, open(socket)}
  end

  def handle_event("close_bulk_write_property", _params, socket) do
    {:noreply, close(socket)}
  end

  def handle_event("change_bulk_write_property", params, socket) do
    {:noreply, change(socket, params)}
  end

  def handle_event("submit_bulk_write_property", params, socket) do
    {:noreply, submit(socket, params)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @spec apply_row(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def apply_row(socket, update) when is_map(update) do
    case socket.assigns.bulk_write_property do
      nil ->
        socket

      modal ->
        assign(socket, :bulk_write_property, put_row(modal, update))
    end
  end

  @spec finish(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def finish(socket) do
    case socket.assigns.bulk_write_property do
      nil ->
        socket

      modal ->
        assign(socket, :bulk_write_property, %{modal | busy: false})
    end
  end

  defp open(socket) do
    objects = selected_objects(socket)

    if objects == [] do
      put_flash(socket, :error, gt("Kein Objekt zum Schreiben ausgewählt."))
    else
      properties = property_options(objects)

      assign(socket, :bulk_write_property, %{
        properties: properties,
        property: default_property(properties),
        value: "",
        priority: socket.assigns.write_priority,
        busy: false,
        objects: objects,
        rows: Enum.map(objects, &build_row/1)
      })
    end
  end

  defp close(socket) do
    case socket.assigns.bulk_write_property do
      %{busy: true} -> socket
      _modal -> assign(socket, :bulk_write_property, nil)
    end
  end

  defp change(socket, params) do
    case socket.assigns.bulk_write_property do
      %{busy: true} = _modal ->
        socket

      nil ->
        socket

      modal ->
        form = form_params(params)
        property = selected_property(form["property"], modal.properties) || modal.property
        value = Map.get(form, "value", modal.value)
        priority = WriteFormParams.parse_priority(form["priority"]) || modal.priority

        assign(socket, :bulk_write_property, %{
          modal
          | property: property,
            value: value,
            priority: priority
        })
    end
  end

  defp submit(socket, params) do
    case socket.assigns.bulk_write_property do
      %{busy: true} = _modal ->
        socket

      nil ->
        socket

      %{properties: []} = _modal ->
        socket

      modal ->
        form = form_params(params)

        case selected_property(form["property"], modal.properties) do
          nil ->
            put_flash(socket, :error, gt("Bitte eine Eigenschaft wählen."))

          property ->
            value = Map.get(form, "value", "")
            priority = WriteFormParams.parse_priority(form["priority"]) || modal.priority
            start_write(socket, modal, property, value, priority)
        end
    end
  end

  defp start_write(socket, modal, property, value, priority) do
    if String.trim(value) == "" do
      put_flash(socket, :error, gt("Bitte einen Wert eingeben."))
    else
      {jobs, rows} = prepare_rows(modal, property, value)

      socket =
        if property == :present_value do
          assign(socket, :write_priority, priority)
        else
          socket
        end

      modal = %{modal | property: property, value: value, priority: priority, rows: rows}

      case jobs do
        [] ->
          assign(socket, :bulk_write_property, %{modal | busy: false})

        jobs ->
          case BulkPropertyWrite.start(
                 self(),
                 socket.assigns.device_id,
                 property,
                 jobs,
                 priority
               ) do
            :async ->
              assign(socket, :bulk_write_property, %{modal | busy: true})

            {:sync, results} ->
              finished = Enum.reduce(results, modal, fn result, acc -> put_row(acc, result) end)
              assign(socket, :bulk_write_property, %{finished | busy: false})
          end
      end
    end
  end

  defp prepare_rows(modal, property, value) do
    {rows, jobs} =
      Enum.map_reduce(modal.objects, [], fn object, jobs_acc ->
        row = build_row(object)

        case BulkPropertyWrite.parse_value(property, value, object) do
          {:ok, parsed} ->
            {row_with(row, :queued, nil), [{object, parsed} | jobs_acc]}

          {:error, reason} ->
            {row_with(row, :error, reason), jobs_acc}
        end
      end)

    {Enum.reverse(jobs), rows}
  end

  defp put_row(modal, %{type: type, instance: instance} = update) do
    rows =
      Enum.map(modal.rows, fn row ->
        if row.type == type and row.instance == instance do
          row_with(row, update.status, Map.get(update, :reason))
        else
          row
        end
      end)

    %{modal | rows: rows}
  end

  defp row_with(row, status, reason) do
    %{row | status: status, message: row_message(status, reason)}
  end

  defp row_message(:error, reason), do: error_message(reason)
  defp row_message(_status, _reason), do: nil

  defp error_message(:empty_value), do: gt("Bitte einen Wert eingeben.")
  defp error_message(:invalid_boolean), do: gt("erwartet true/false")
  defp error_message(:invalid_number), do: gt("erwartet Zahl")
  defp error_message(:invalid_enum), do: gt("erwartet Aufzählungswert")

  defp error_message(:out_of_range),
    do: gt("Der Wert liegt ausserhalb des erlaubten Bereichs.")

  defp error_message(:unsupported_property),
    do: gt("Diese Eigenschaft kann nicht als Text geschrieben werden.")

  defp error_message(reason), do: ErrorMessage.format_reason(reason)

  defp property_options(objects) do
    objects
    |> BulkPropertyWrite.candidate_properties()
    |> Enum.map(fn id -> %{id: id, label: PropertyExport.property_label(id)} end)
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  defp default_property(properties) do
    ids = MapSet.new(properties, & &1.id)

    Enum.find([:present_value, :description, :out_of_service], &MapSet.member?(ids, &1)) ||
      case properties do
        [%{id: id} | _rest] -> id
        [] -> nil
      end
  end

  defp selected_property(raw, properties) when is_binary(raw) do
    case Enum.find(properties, &(Atom.to_string(&1.id) == raw)) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp selected_property(_raw, _properties), do: nil

  defp selected_objects(socket) do
    selected = socket.assigns.selected_object_keys

    Enum.filter(socket.assigns.objects, fn object ->
      MapSet.member?(selected, {object.type, object.instance})
    end)
  end

  defp build_row(object) do
    %{
      type: object.type,
      instance: object.instance,
      name: display_name(object),
      type_label: ObjectTypes.short_label(object.type),
      status: :ready,
      message: nil
    }
  end

  defp display_name(object) do
    case Map.get(object, :name) do
      name when is_binary(name) and name != "" -> name
      _missing -> "#{object.type}:#{object.instance}"
    end
  end

  defp form_params(params) when is_map(params) do
    Map.get(params, "bulk_write", params)
  end
end
