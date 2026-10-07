defmodule BacViewWeb.MultiEdeExportLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.EdeExport
  alias BacViewWeb.LiveFlash

  @form_as :ede_export

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket), do: assign(socket, :multi_ede_export, nil)

  @spec open(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def open(socket) do
    devices = list_device_rows()
    selected = for device <- devices, device.loaded?, do: device.id
    available = object_types_for(selected)
    types = EdeExport.default_selected_object_types(available)

    form =
      build_form(
        %{
          "project_name" => default_project_name(devices, selected),
          "version" => "1.0.0",
          "author" => "BacView",
          "include_state_texts" => false
        },
        types,
        selected
      )

    assign(socket, :multi_ede_export, %{
      devices: devices,
      available_types: available,
      form: form
    })
  end

  @spec close(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close(socket), do: assign(socket, :multi_ede_export, nil)

  @spec change(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def change(socket, params) do
    update_state(socket, fn state ->
      form_params = Map.get(params, "ede_export", %{})
      selected = selected_device_ids(form_params, state.devices)
      available = object_types_for(selected)
      submitted = parse_object_types(form_params["object_types"])
      types = reconcile_object_types(submitted, state.available_types, available)
      %{state | available_types: available, form: build_form(form_params, types, selected)}
    end)
  end

  @spec select_all_types(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_all_types(socket) do
    update_types(socket, fn state -> Enum.map(state.available_types, & &1.type) end)
  end

  @spec select_default_types(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_default_types(socket) do
    update_types(socket, fn state ->
      EdeExport.default_selected_object_types(state.available_types)
    end)
  end

  @spec select_all_devices(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_all_devices(socket) do
    update_device_selection(socket, fn state ->
      for device <- state.devices, device.loaded?, do: device.id
    end)
  end

  @spec select_no_devices(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_no_devices(socket) do
    update_device_selection(socket, fn _state -> [] end)
  end

  @spec export(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def export(socket, params) do
    case socket.assigns.multi_ede_export do
      nil ->
        socket

      state ->
        form_params = Map.get(params, "ede_export", %{})
        selected = selected_device_ids(form_params, state.devices)
        available = object_types_for(selected)
        submitted = parse_object_types(form_params["object_types"])
        types = reconcile_object_types(submitted, state.available_types, available)

        socket =
          assign(socket, :multi_ede_export, %{
            state
            | available_types: available,
              form: build_form(form_params, types, selected)
          })

        opts = [
          project_name: trim(form_params["project_name"]),
          version: trim(form_params["version"]),
          author: trim(form_params["author"]),
          include_state_texts: truthy?(form_params["include_state_texts"]),
          object_types: types
        ]

        case EdeExport.export_many(selected, opts) do
          {:ok, %{files: files}} ->
            socket = push_files(socket, files)
            close(socket)

          {:error, reason} ->
            LiveFlash.put_error(socket, :export_ede, reason)
        end
    end
  end

  @doc false
  @spec reconcile_object_types([atom() | integer()], [map() | atom() | integer()], [
          map() | atom() | integer()
        ]) :: [atom() | integer()]
  def reconcile_object_types(submitted, old_available, new_available)
      when is_list(submitted) and is_list(old_available) and is_list(new_available) do
    new_types = MapSet.new(Enum.map(new_available, &type_of/1))
    old_types = MapSet.new(Enum.map(old_available, &type_of/1))
    added = MapSet.difference(new_types, old_types)

    added_entries = Enum.filter(new_available, &MapSet.member?(added, type_of(&1)))
    default_added = EdeExport.default_selected_object_types(added_entries)

    submitted
    |> MapSet.new()
    |> MapSet.intersection(new_types)
    |> MapSet.union(MapSet.new(default_added))
    |> Enum.sort_by(&to_string/1)
  end

  defp update_state(socket, fun) do
    case socket.assigns.multi_ede_export do
      nil -> socket
      state -> assign(socket, :multi_ede_export, fun.(state))
    end
  end

  defp update_types(socket, fun) do
    update_state(socket, fn state ->
      current = form_params(state.form)
      selected = selected_device_ids(current, state.devices)
      %{state | form: build_form(current, fun.(state), selected)}
    end)
  end

  defp update_device_selection(socket, fun) do
    update_state(socket, fn state ->
      selected = fun.(state)
      available = object_types_for(selected)
      current = form_params(state.form)
      submitted = parse_object_types(current["object_types"])
      types = reconcile_object_types(submitted, state.available_types, available)

      %{
        state
        | available_types: available,
          form: build_form(current, types, selected)
      }
    end)
  end

  defp push_files(socket, files) do
    Enum.reduce(files, socket, fn file, sock ->
      push_event(sock, "download_file", %{
        content: file.content,
        filename: file.filename,
        mime: file.mime
      })
    end)
  end

  defp list_device_rows() do
    devices = Discovery.list_devices()

    devices
    |> Enum.map(&device_row/1)
    |> Enum.filter(&is_integer(&1.id))
  end

  defp device_row(device) do
    id = Map.get(device, :id) || Map.get(device, :instance)
    instance = Map.get(device, :instance) || id
    status = Map.get(device, :status)

    %{
      id: id,
      instance: instance,
      name: trimmed_name(Map.get(device, :name)),
      status: status,
      loaded?: status == :loaded and is_integer(id),
      object_count: Map.get(device, :object_count)
    }
  end

  defp trimmed_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed_name(_name), do: nil

  defp default_project_name(devices, selected_ids) do
    selected = Enum.filter(devices, &(&1.id in selected_ids))

    case selected do
      [%{name: name}] when is_binary(name) -> name
      [%{instance: instance}] when is_integer(instance) -> "Device #{instance}"
      _other -> "BacView"
    end
  end

  defp object_types_for(device_ids) do
    device_ids
    |> scanned_for()
    |> EdeExport.available_object_types()
  end

  defp scanned_for(device_ids) do
    Enum.flat_map(device_ids, &safe_scanned/1)
  end

  defp safe_scanned(device_id) do
    DeviceSession.scanned(device_id)
  catch
    :exit, _reason -> []
  end

  defp selected_device_ids(params, devices) do
    allowed =
      devices
      |> Enum.filter(& &1.loaded?)
      |> MapSet.new(& &1.id)

    params
    |> Map.get("device_ids", Map.get(params, :device_ids))
    |> parse_device_ids()
    |> Enum.filter(&MapSet.member?(allowed, &1))
  end

  defp build_form(params, object_types, device_ids) do
    params = stringify_keys(params)

    to_form(
      %{
        "project_name" => trim(params["project_name"]),
        "version" => trim(params["version"]),
        "author" => trim(params["author"]),
        "include_state_texts" => truthy?(params["include_state_texts"]),
        "object_types" => Enum.map(object_types, &to_string/1),
        "device_ids" => Enum.map(device_ids, &Integer.to_string/1)
      },
      as: @form_as
    )
  end

  defp form_params(%{params: params}) when is_map(params) and map_size(params) > 0 do
    stringify_keys(params)
  end

  defp form_params(%{source: source}) when is_map(source), do: stringify_keys(source)
  defp form_params(_form), do: %{}

  defp stringify_keys(source) do
    Map.new(source, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp parse_device_ids(nil), do: []

  defp parse_device_ids(ids) when is_list(ids),
    do: ids |> Enum.map(&parse_device_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp parse_device_ids(id), do: parse_device_ids([id])

  defp parse_device_id(id) when is_integer(id) and id >= 0, do: id

  defp parse_device_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {int, ""} when int >= 0 -> int
      _other -> nil
    end
  end

  defp parse_device_id(_id), do: nil

  defp parse_object_types(nil), do: []

  defp parse_object_types(types) when is_list(types),
    do: types |> Enum.map(&parse_object_type/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp parse_object_types(type), do: parse_object_types([type])

  defp parse_object_type(type) when is_atom(type), do: type
  defp parse_object_type(type) when is_integer(type), do: type

  defp parse_object_type(type) when is_binary(type) do
    trimmed = String.trim(type)

    case Integer.parse(trimmed) do
      {int, ""} ->
        int

      _other ->
        try do
          String.to_existing_atom(trimmed)
        rescue
          ArgumentError -> nil
        end
    end
  end

  defp parse_object_type(_type), do: nil

  defp type_of(%{type: type}), do: type
  defp type_of(type), do: type

  defp truthy?(value), do: value in [true, "true", "on", "1", 1]

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: ""
end
