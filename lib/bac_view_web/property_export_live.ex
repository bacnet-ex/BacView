defmodule BacViewWeb.PropertyExportLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.PropertyExport
  alias BacViewWeb.LiveFlash

  @form_as :property_export

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket), do: assign(socket, :property_export, nil)

  @spec open(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def open(socket) do
    devices = list_device_rows()
    selected = for device <- devices, device.loaded?, do: device.id
    objects = entries_for(devices, selected)
    properties = properties_for(objects, Enum.map(objects, & &1.key))

    assign(socket, :property_export, %{
      devices: devices,
      objects: objects,
      available_properties: properties,
      form: build_form("csv", "", [], [], selected)
    })
  end

  @spec close(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close(socket), do: assign(socket, :property_export, nil)

  @spec change(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def change(socket, params) do
    update_state(socket, fn state ->
      current = form_params(Map.get(params, "property_export", %{}))
      previous = selected_device_ids(form_params(state.form), state.devices)
      device_ids = selected_device_ids(current, state.devices)
      objects = entries_for(state.devices, device_ids)
      submitted = parse_object_keys(current["object_keys"])
      object_keys = reconcile_objects(submitted, previous, device_ids, objects)
      apply_selection(state, objects, device_ids, object_keys, current)
    end)
  end

  @spec select_all_devices(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_all_devices(socket) do
    update_devices(socket, fn state ->
      for device <- state.devices, device.loaded?, do: device.id
    end)
  end

  @spec select_no_devices(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_no_devices(socket) do
    update_state(socket, fn state ->
      current = form_params(state.form)

      %{
        state
        | objects: [],
          available_properties: [],
          form: build_form(normalize_format(current["format"]), "", [], [], [], current)
      }
    end)
  end

  @spec select_visible_objects(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_visible_objects(socket) do
    update_object_keys(socket, fn selected, objects, current ->
      visible = visible_object_keys(objects, current)
      Enum.uniq(selected ++ visible)
    end)
  end

  @spec select_no_visible_objects(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_no_visible_objects(socket) do
    update_object_keys(socket, fn selected, objects, current ->
      visible = MapSet.new(visible_object_keys(objects, current))
      Enum.reject(selected, &MapSet.member?(visible, &1))
    end)
  end

  @spec select_all_properties(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_all_properties(socket) do
    update_state(socket, fn state ->
      current = form_params(state.form)
      device_ids = selected_device_ids(current, state.devices)
      object_keys = parse_object_keys(current["object_keys"])
      selected = PropertyExport.parse_identifier_list(current["property_ids"])
      visible_ids = visible_property_ids(state.available_properties, current["property_query"])
      selected_set = MapSet.new(selected)
      visible_set = MapSet.new(visible_ids)

      property_ids =
        state.available_properties
        |> Enum.map(& &1.id)
        |> Enum.filter(fn id ->
          MapSet.member?(selected_set, id) or MapSet.member?(visible_set, id)
        end)

      %{
        state
        | form:
            build_form(
              normalize_format(current["format"]),
              normalize_filter(current["object_type"], state.objects),
              property_ids,
              object_keys,
              device_ids,
              current
            )
      }
    end)
  end

  @spec select_no_properties(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def select_no_properties(socket) do
    update_state(socket, fn state ->
      current = form_params(state.form)
      device_ids = selected_device_ids(current, state.devices)
      object_keys = parse_object_keys(current["object_keys"])

      visible =
        MapSet.new(visible_property_ids(state.available_properties, current["property_query"]))

      property_ids =
        current["property_ids"]
        |> PropertyExport.parse_identifier_list()
        |> Enum.reject(&MapSet.member?(visible, &1))

      %{
        state
        | form:
            build_form(
              normalize_format(current["format"]),
              normalize_filter(current["object_type"], state.objects),
              property_ids,
              object_keys,
              device_ids,
              current
            )
      }
    end)
  end

  @spec export(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def export(socket, params) do
    socket = change(socket, params)

    case socket.assigns.property_export do
      nil ->
        socket

      state ->
        current = form_params(state.form)
        device_ids = selected_device_ids(current, state.devices)
        object_keys = parse_object_keys(current["object_keys"])
        property_ids = PropertyExport.parse_identifier_list(current["property_ids"])
        format = export_format(current["format"])
        groups = load_groups(state.devices, device_ids)

        case PropertyExport.export(groups, object_keys, property_ids, format) do
          {:ok, file} ->
            socket
            |> push_event("download_file", %{
              content: file.content,
              filename: file.filename,
              mime: file.mime
            })
            |> close()

          {:error, reason} ->
            LiveFlash.put_error(socket, :export_properties, reason)
        end
    end
  end

  @doc false
  @spec reconcile_objects([String.t()], [integer()], [integer()], [map()]) :: [String.t()]
  def reconcile_objects(submitted, old_device_ids, new_device_ids, objects)
      when is_list(submitted) and is_list(old_device_ids) and is_list(new_device_ids) and
             is_list(objects) do
    valid = MapSet.new(objects, & &1.key)
    added_devices = MapSet.difference(MapSet.new(new_device_ids), MapSet.new(old_device_ids))

    kept = Enum.filter(submitted, &MapSet.member?(valid, &1))

    added =
      objects
      |> Enum.filter(&MapSet.member?(added_devices, &1.device_id))
      |> Enum.map(& &1.key)

    Enum.uniq(kept ++ added)
  end

  @doc false
  @spec reconcile_properties([PropertyExport.property_id()], [map()], [map()]) :: [
          PropertyExport.property_id()
        ]
  def reconcile_properties(submitted, old_available, new_available)
      when is_list(submitted) and is_list(old_available) and is_list(new_available) do
    new_ids = MapSet.new(Enum.map(new_available, & &1.id))
    old_ids = MapSet.new(Enum.map(old_available, & &1.id))
    added = MapSet.difference(new_ids, old_ids)

    submitted
    |> MapSet.new()
    |> MapSet.intersection(new_ids)
    |> MapSet.union(added)
    |> Enum.sort_by(&PropertyExport.property_label/1)
  end

  defp update_state(socket, fun) do
    case socket.assigns.property_export do
      nil -> socket
      state -> assign(socket, :property_export, fun.(state))
    end
  end

  defp update_devices(socket, fun) do
    update_state(socket, fn state ->
      current = form_params(state.form)
      previous = selected_device_ids(current, state.devices)
      device_ids = fun.(state)
      objects = entries_for(state.devices, device_ids)
      submitted = parse_object_keys(current["object_keys"])
      object_keys = reconcile_objects(submitted, previous, device_ids, objects)
      apply_selection(state, objects, device_ids, object_keys, current)
    end)
  end

  defp update_object_keys(socket, fun) do
    update_state(socket, fn state ->
      current = form_params(state.form)
      device_ids = selected_device_ids(current, state.devices)
      selected = parse_object_keys(current["object_keys"])
      object_keys = fun.(selected, state.objects, current)
      apply_selection(state, state.objects, device_ids, object_keys, current)
    end)
  end

  defp apply_selection(state, objects, device_ids, object_keys, current) do
    known = MapSet.new(objects, & &1.key)
    object_keys = Enum.filter(object_keys, &MapSet.member?(known, &1))
    # No object is checked yet, so keep the full property list visible and unchecked.
    source_keys = if object_keys == [], do: MapSet.to_list(known), else: object_keys
    properties = properties_for(objects, source_keys)
    submitted_props = PropertyExport.parse_identifier_list(current["property_ids"])
    property_ids = reconcile_properties(submitted_props, state.available_properties, properties)

    %{
      state
      | objects: objects,
        available_properties: properties,
        form:
          build_form(
            normalize_format(current["format"]),
            normalize_filter(current["object_type"], objects),
            property_ids,
            object_keys,
            device_ids,
            current
          )
    }
  end

  defp visible_object_keys(objects, current) do
    objects
    |> PropertyExport.filter_objects(current["object_type"], current["object_query"])
    |> Enum.map(& &1.key)
  end

  defp visible_property_ids(properties, query) do
    properties
    |> PropertyExport.filter_properties(query)
    |> Enum.map(& &1.id)
  end

  defp entries_for(devices, device_ids) do
    by_id = Map.new(devices, &{&1.id, &1})

    device_ids
    |> Enum.flat_map(fn id ->
      case Map.get(by_id, id) do
        nil ->
          []

        device ->
          PropertyExport.entries(
            %{id: device.id, instance: device.instance, name: device.name},
            safe_scanned(id)
          )
      end
    end)
    |> Enum.sort_by(&{&1.device_instance, String.downcase(&1.type_label), &1.instance})
  end

  defp properties_for(objects, keys) do
    selected = MapSet.new(keys)

    objects
    |> Enum.filter(&MapSet.member?(selected, &1.key))
    |> Enum.flat_map(& &1.property_ids)
    |> Enum.uniq()
    |> Enum.map(fn id ->
      %{
        id: id,
        token: PropertyExport.property_token(id),
        label: PropertyExport.property_label(id)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  defp load_groups(devices, device_ids) do
    by_id = Map.new(devices, &{&1.id, &1})

    Enum.flat_map(device_ids, fn id ->
      case Map.get(by_id, id) do
        nil ->
          []

        device ->
          [
            %{
              device_id: device.id,
              device_instance: device.instance,
              device_name: device.name,
              scanned: safe_scanned(id)
            }
          ]
      end
    end)
  end

  defp safe_scanned(device_id) do
    DeviceSession.scanned(device_id)
  catch
    :exit, _reason -> []
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

    %{
      id: id,
      instance: instance,
      name: trimmed_name(Map.get(device, :name)),
      status: Map.get(device, :status),
      loaded?: Map.get(device, :status) == :loaded and is_integer(id),
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

  defp selected_device_ids(params, devices) do
    allowed =
      devices
      |> Enum.filter(& &1.loaded?)
      |> MapSet.new(& &1.id)

    params
    |> Map.get("device_ids", [])
    |> parse_device_ids()
    |> Enum.filter(&MapSet.member?(allowed, &1))
  end

  defp build_form(format, object_type, property_ids, object_keys, device_ids, current \\ %{}) do
    to_form(
      %{
        "format" => format,
        "object_type" => object_type,
        "object_query" => query_text(current["object_query"]),
        "property_query" => query_text(current["property_query"]),
        "property_ids" => Enum.map(property_ids, &PropertyExport.property_token/1),
        "object_keys" => object_keys,
        "device_ids" => Enum.map(device_ids, &Integer.to_string/1)
      },
      as: @form_as
    )
  end

  defp query_text(value) when is_binary(value), do: value
  defp query_text(_value), do: ""

  defp form_params(%{params: params}) when is_map(params) and map_size(params) > 0 do
    stringify_keys(params)
  end

  defp form_params(%{source: source}) when is_map(source), do: stringify_keys(source)
  defp form_params(params) when is_map(params), do: stringify_keys(params)
  defp form_params(_form), do: %{}

  defp stringify_keys(source) do
    Map.new(source, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp parse_device_ids(nil), do: []

  defp parse_device_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_device_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_device_ids(id), do: parse_device_ids([id])

  defp parse_device_id(id) when is_integer(id) and id >= 0, do: id

  defp parse_device_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {int, ""} when int >= 0 -> int
      _other -> nil
    end
  end

  defp parse_device_id(_id), do: nil

  defp parse_object_keys(nil), do: []

  defp parse_object_keys(keys) when is_list(keys) do
    keys
    |> Enum.map(&parse_object_key/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_object_keys(key), do: parse_object_keys([key])

  defp parse_object_key(key) when is_binary(key) do
    case String.split(key, "|") do
      [device_id, type, instance] ->
        with {dev, ""} <- Integer.parse(device_id),
             true <- dev >= 0,
             {inst, ""} <- Integer.parse(instance),
             true <- inst >= 0,
             {:ok, _parsed} <- PropertyExport.parse_identifier(type) do
          key
        else
          _invalid -> nil
        end

      _parts ->
        nil
    end
  end

  defp parse_object_key(_key), do: nil

  defp normalize_filter(filter, objects) do
    case PropertyExport.parse_identifier(filter) do
      {:ok, type} ->
        if Enum.any?(objects, &(&1.type == type)) do
          PropertyExport.property_token(type)
        else
          ""
        end

      :error ->
        ""
    end
  end

  defp normalize_format(format) when format in ["json", :json], do: "json"
  defp normalize_format(_format), do: "csv"

  defp export_format("json"), do: :json
  defp export_format(_format), do: :csv
end
