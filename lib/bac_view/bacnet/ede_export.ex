defmodule BacView.BACnet.EdeExport do
  @moduledoc """
  Builds BACnet EDE files from a device session's scanned objects using `bacnet_ede`.
  """

  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnetEDE.Project
  alias BACnetEDE.Project.Object, as: EdeObject
  alias BACnetEDE.StateTexts
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.ObjectTypes
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.Text

  @type export_file :: %{filename: String.t(), content: binary(), mime: String.t()}
  @type object_type_entry :: %{
          type: atom() | integer(),
          label: String.t(),
          count: non_neg_integer()
        }

  @csv_mime "text/csv; charset=utf-8"
  @default_excluded_types [:file, :structured_view]
  @unit_object_types [
    :accumulator,
    :analog_input,
    :analog_output,
    :analog_value,
    :integer_value,
    :large_analog_value,
    :positive_integer_value,
    :pulse_converter
  ]
  # MAJOR.MINOR.PATCH with optional pre-release / build metadata (SemVer 2.0.0)
  @semver_regex ~r/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/

  @doc """
  Exports EDE CSV data for a loaded device.

  Options (from the export modal):
  - `:project_name` (required, non-empty)
  - `:version` (required, semantic version e.g. `1.0.0`)
  - `:author` (optional, default `""`)
  - `:include_state_texts` (boolean, default `false`)
  - `:object_types` (list of type atoms/integers to include; required non-empty)
  """
  @spec export(integer(), keyword()) :: {:ok, %{files: [export_file()]}} | {:error, term()}
  def export(device_id, opts \\ []) when is_integer(device_id) and is_list(opts) do
    with {:ok, meta} <- normalize_meta(opts),
         {:ok, device_instance} <- fetch_device_instance(device_id),
         scanned when scanned != [] <- DeviceSession.scanned(device_id) do
      do_export(scanned, device_instance, meta)
    else
      [] -> {:error, :no_objects}
      {:error, _reason} = err -> err
    end
  end

  @doc """
  Object types present on the device (from scanned pairs or summary objects),
  sorted by localized short label.
  """
  @spec available_object_types([{ObjectIdentifier.t(), term()}] | [map()]) :: [
          object_type_entry()
        ]
  def available_object_types(items) when is_list(items) do
    items
    |> Enum.map(&entry_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.map(fn {type, count} ->
      %{type: type, label: ObjectTypes.short_label(type), count: count}
    end)
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  @doc """
  Default selection: every available type except `file`.
  """
  @spec default_selected_object_types([object_type_entry()] | [atom() | integer()]) :: [
          atom() | integer()
        ]
  def default_selected_object_types(available) when is_list(available) do
    available
    |> Enum.map(fn
      %{type: type} -> type
      type -> type
    end)
    |> Enum.reject(&(&1 in @default_excluded_types))
  end

  @doc """
  Builds EDE export files from an in-memory scanned list (used by tests and `export/2`).
  """
  @spec export_from_scanned(
          [{ObjectIdentifier.t(), map() | struct()}],
          non_neg_integer(),
          keyword() | map()
        ) :: {:ok, %{files: [export_file()]}} | {:error, term()}
  def export_from_scanned(scanned, device_instance, meta)
      when is_list(scanned) and is_integer(device_instance) do
    with {:ok, meta} <- normalize_meta(meta) do
      do_export(scanned, device_instance, meta)
    end
  end

  defp do_export(scanned, device_instance, meta) do
    with {:ok, project, state_texts} <- build_project(scanned, device_instance, meta),
         {:ok, ede_csv} <- BACnetEDE.to_binary(project) do
      prefix = filename_prefix(meta.project_name)

      ede_file = %{
        filename: "#{prefix}_EDE.csv",
        content: ede_csv,
        mime: @csv_mime
      }

      with {:ok, files} <- maybe_append_state_texts(ede_file, state_texts, meta, prefix) do
        {:ok, %{files: files}}
      end
    end
  end

  defp maybe_append_state_texts(ede_file, state_texts, meta, prefix) do
    if meta.include_state_texts and map_size(state_texts.texts) > 0 do
      case StateTexts.to_binary(state_texts) do
        {:ok, st_csv} ->
          st_file = %{
            filename: "#{prefix}_StateTexts.csv",
            content: st_csv,
            mime: @csv_mime
          }

          {:ok, [ede_file, st_file]}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, [ede_file]}
    end
  end

  @doc false
  @spec build_project(
          [{ObjectIdentifier.t(), map() | struct()}],
          non_neg_integer(),
          map()
        ) :: {:ok, Project.t(), StateTexts.t()} | {:error, term()}
  def build_project(scanned, device_instance, meta)
      when is_list(scanned) and is_integer(device_instance) and is_map(meta) do
    allowed = MapSet.new(meta.object_types)

    {objects, state_texts_map} =
      scanned
      |> Enum.filter(fn entry ->
        case entry_type(entry) do
          nil -> false
          type -> MapSet.member?(allowed, type)
        end
      end)
      |> Enum.reduce({%{}, %{}, MapSet.new(), 1}, fn entry, acc ->
        map_scanned_entry(entry, device_instance, meta.include_state_texts, acc)
      end)
      |> then(fn {objects, texts, _used_keys, _next_ref} -> {objects, texts} end)

    if map_size(objects) == 0 do
      {:error, :no_objects}
    else
      project = %Project{
        project_name: meta.project_name,
        version: meta.version,
        timestamp_last_change: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
        author_last_change: meta.author,
        layout_version: "2.3",
        objects: objects
      }

      if Project.valid?(project) do
        {:ok, project, %StateTexts{texts: state_texts_map}}
      else
        {:error, :invalid_project}
      end
    end
  end

  defp normalize_meta(meta) when is_list(meta), do: normalize_meta(Map.new(meta))

  defp normalize_meta(meta) when is_map(meta) do
    project_name = meta |> Map.get(:project_name, Map.get(meta, "project_name", "")) |> to_trim()
    version = meta |> Map.get(:version, Map.get(meta, "version", "")) |> to_trim()
    author = meta |> Map.get(:author, Map.get(meta, "author", "")) |> to_trim()

    include_state_texts =
      case Map.get(meta, :include_state_texts, Map.get(meta, "include_state_texts", false)) do
        true -> true
        "true" -> true
        "on" -> true
        "1" -> true
        1 -> true
        _other -> false
      end

    object_types =
      parse_object_types(Map.get(meta, :object_types, Map.get(meta, "object_types")))

    cond do
      project_name == "" ->
        {:error, :invalid_project_name}

      not semver?(version) ->
        {:error, :invalid_version}

      object_types == [] ->
        {:error, :no_object_types_selected}

      true ->
        {:ok,
         %{
           project_name: project_name,
           version: version,
           author: author,
           include_state_texts: include_state_texts,
           object_types: object_types
         }}
    end
  end

  defp semver?(version) when is_binary(version), do: Regex.match?(@semver_regex, version)

  defp parse_object_types(nil), do: []
  defp parse_object_types([]), do: []

  defp parse_object_types(types) when is_list(types) do
    types
    |> Enum.map(&parse_object_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_object_types(type), do: parse_object_types([type])

  defp parse_object_type(type) when is_atom(type), do: type
  defp parse_object_type(type) when is_integer(type), do: type

  defp parse_object_type(type) when is_binary(type) do
    trimmed = String.trim(type)

    cond do
      trimmed == "" ->
        nil

      match?({_int, ""}, Integer.parse(trimmed)) ->
        {int, ""} = Integer.parse(trimmed)
        int

      true ->
        try do
          String.to_existing_atom(trimmed)
        rescue
          ArgumentError -> nil
        end
    end
  end

  defp parse_object_type(_type), do: nil

  defp entry_type({%ObjectIdentifier{type: type}, _obj}), do: type
  defp entry_type(%{type: type}), do: type
  defp entry_type(%{object_id: %ObjectIdentifier{type: type}}), do: type
  defp entry_type(_entry), do: nil

  defp to_trim(value) when is_binary(value), do: String.trim(value)
  defp to_trim(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp to_trim(_value), do: ""

  defp fetch_device_instance(device_id) do
    case Discovery.get_device(device_id) do
      {:ok, %{instance: instance}} when is_integer(instance) -> {:ok, instance}
      {:ok, %{object: %ObjectIdentifier{instance: instance}}} -> {:ok, instance}
      :error -> {:error, :device_not_loaded}
      _other -> {:error, :device_not_loaded}
    end
  rescue
    ArgumentError -> {:error, :device_not_loaded}
  end

  defp map_scanned_entry(
         {%ObjectIdentifier{} = oid, obj},
         device_instance,
         include_state_texts,
         {objects, texts, used_keys, next_ref}
       )
       when is_map(obj) do
    case object_type_code(oid.type) do
      nil ->
        {objects, texts, used_keys, next_ref}

      type_code ->
        base_name = object_name(obj, oid)
        keyname = unique_keyname(base_name, oid, used_keys)

        {state_text_ref, texts, next_ref} =
          maybe_state_text(obj, oid, include_state_texts, texts, next_ref)

        ede_object =
          EdeObject.new(
            keyname: keyname,
            device_instance: device_instance,
            object_name: base_name,
            object_type: type_code,
            object_instance: oid.instance,
            description: object_description(obj),
            default_present_value: default_present_value(obj),
            min_present_value: float_field(obj, :min_present_value),
            max_present_value: float_field(obj, :max_present_value),
            settable: settable?(obj),
            supports_cov: supports_cov?(obj),
            high_limit: float_field(obj, :high_limit),
            low_limit: float_field(obj, :low_limit),
            state_text_ref: state_text_ref,
            unit_code: unit_code(obj, oid.type),
            vendor_specific_address: nil,
            notification_class: notification_class(obj)
          )

        if EdeObject.valid?(ede_object) do
          {
            Map.put(objects, keyname, ede_object),
            texts,
            MapSet.put(used_keys, keyname),
            next_ref
          }
        else
          {objects, texts, used_keys, next_ref}
        end
    end
  end

  defp map_scanned_entry(_entry, _device_instance, _include, acc), do: acc

  defp object_type_code(type) when is_integer(type) and type >= 0, do: type

  defp object_type_code(type) when is_atom(type) do
    case Constants.by_name(:object_type, type) do
      {:ok, code} when is_integer(code) -> code
      _other -> nil
    end
  end

  defp object_type_code(_type), do: nil

  defp object_name(obj, %ObjectIdentifier{type: type, instance: instance}) do
    name =
      case Map.get(obj, :object_name) || Map.get(obj, :name) do
        value when is_binary(value) ->
          case String.trim(value) do
            "" -> nil
            trimmed -> Text.sanitize_utf8(trimmed) || trimmed
          end

        _other ->
          nil
      end

    name || "#{type}_#{instance}"
  end

  defp unique_keyname(base_name, %ObjectIdentifier{type: type, instance: instance}, used_keys) do
    if MapSet.member?(used_keys, base_name) do
      candidate = "#{base_name} (#{type}:#{instance})"

      if MapSet.member?(used_keys, candidate),
        do: "#{candidate}-#{System.unique_integer([:positive])}",
        else: candidate
    else
      base_name
    end
  end

  defp object_description(obj) do
    case Map.get(obj, :description) do
      desc when is_binary(desc) ->
        case String.trim(desc) do
          "" -> nil
          trimmed -> Text.sanitize_utf8(trimmed) || trimmed
        end

      _other ->
        nil
    end
  end

  defp default_present_value(obj) do
    case Map.get(obj, :relinquish_default) do
      nil -> nil
      value -> scalar_string(value)
    end
  end

  defp scalar_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> Text.sanitize_utf8(trimmed) || trimmed
    end
  end

  defp scalar_string(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp scalar_string(value) when is_integer(value), do: Integer.to_string(value)

  defp scalar_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, decimals: 15])

  defp scalar_string(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar_string(_value), do: nil

  defp float_field(obj, key) do
    case Map.get(obj, key) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      _other -> nil
    end
  end

  defp settable?(obj) when is_map(obj) do
    (Map.has_key?(obj, :present_value) and Map.has_key?(obj, :priority_array)) or
      (Map.has_key?(obj, :present_value) and not Map.has_key?(obj, :out_of_service))
  end

  defp supports_cov?(obj) when is_map(obj) do
    if Map.has_key?(obj, :cov_increment), do: true, else: nil
  end

  defp notification_class(obj) do
    case Map.get(obj, :notification_class) do
      n when is_integer(n) and n >= 0 -> n
      _other -> nil
    end
  end

  defp unit_code(obj, type) when type in @unit_object_types do
    case Map.get(obj, :units) || Map.get(obj, :engineering_units) do
      unit when is_atom(unit) ->
        case Constants.by_name(:engineering_unit, unit) do
          {:ok, code} when is_integer(code) and code >= 0 -> code
          _other -> nil
        end

      unit when is_integer(unit) and unit >= 0 ->
        unit

      _other ->
        nil
    end
  end

  defp unit_code(_obj, _type), do: nil

  defp maybe_state_text(obj, oid, true, texts, next_ref) do
    case state_text_list(obj, oid.type) do
      nil ->
        {nil, texts, next_ref}

      list ->
        case Enum.find(texts, fn {_ref, existing} -> existing == list end) do
          {ref, _list} ->
            {ref, texts, next_ref}

          nil ->
            {next_ref, Map.put(texts, next_ref, list), next_ref + 1}
        end
    end
  end

  defp maybe_state_text(_obj, _oid, _include, texts, next_ref), do: {nil, texts, next_ref}

  defp state_text_list(obj, type) do
    cond do
      MultistateState.multistate_object_type?(type) or MultistateState.multistate_object?(obj) ->
        case MultistateState.state_texts(obj) do
          [] -> nil
          list -> list
        end

      PropertyFormatter.binary_object_type?(type) ->
        inactive = string_prop(obj, :inactive_text)
        active = string_prop(obj, :active_text)

        if is_nil(inactive) and is_nil(active) do
          nil
        else
          [inactive || "", active || ""]
        end

      true ->
        nil
    end
  end

  defp string_prop(obj, key) do
    case Map.get(obj, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> Text.sanitize_utf8(trimmed) || trimmed
        end

      _other ->
        nil
    end
  end

  defp filename_prefix(project_name) do
    project_name
    |> String.replace(~r/[^\w\-.]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "BacView"
      prefix -> prefix
    end
  end
end
