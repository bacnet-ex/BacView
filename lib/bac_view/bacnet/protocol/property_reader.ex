defmodule BacView.BACnet.Protocol.PropertyReader do
  @moduledoc """
  Reads object properties declared on the BACnet object via `ObjectsUtility.get_properties/1`.
  """

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectsUtility
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Segmentation
  alias BacView.Text

  import BACnet.Protocol.ObjectsUtility, only: [is_object: 1]

  @chunk_size 30
  @read_opts [allow_unknown_properties: true]

  @input_object_types [:analog_input, :binary_input, :multi_state_input]

  @trend_log_types [:trend_log, :trend_log_multiple]

  @spec read_all(module(), term(), ObjectIdentifier.t()) :: {:ok, [map()]} | {:error, term()}
  def read_all(client, destination, %ObjectIdentifier{} = object) do
    case fetch_bacnet_object(client, destination, object) do
      {:ok, bacnet_object, :rpm} ->
        with {:ok, properties} <- property_list(bacnet_object),
             {:ok, results} <-
               read_all_properties(
                 client,
                 destination,
                 object,
                 readable_properties(properties, object),
                 :rpm
               ) do
          {:ok, format_results(properties, results, bacnet_object)}
        end

      {:ok, bacnet_object, properties, :individual} ->
        with {:ok, results} <-
               read_all_properties(
                 client,
                 destination,
                 object,
                 readable_properties(properties, object),
                 :individual
               ) do
          {:ok, format_results(properties, results, bacnet_object)}
        end

      {:error, _client} = err ->
        err
    end
  end

  defp readable_properties(properties, %ObjectIdentifier{type: type})
       when type in @trend_log_types do
    Enum.reject(properties, &(&1 == :log_buffer))
  end

  defp readable_properties(properties, _object), do: properties

  @doc false
  @spec format_property_rows([term()], map(), term()) :: [map()]
  def format_property_rows(properties, results, bacnet_object \\ nil)
      when is_list(properties) and is_map(results) do
    format_results(properties, results, bacnet_object)
  end

  defp fetch_bacnet_object(client, destination, object) do
    opts = Keyword.merge(@read_opts, read_level: :all)

    case client.read_object(destination, object, opts) do
      {:ok, obj} when is_object(obj) ->
        {:ok, obj, :rpm}

      {:error, _err} = error ->
        if Segmentation.fallback_error?(error) do
          fetch_bacnet_object_without_rpm(client, destination, object)
        else
          error
        end

      _client ->
        {:error, :object_unavailable}
    end
  end

  # Fallback for devices that do not support segmentation: read the property
  # list and object name individually, then read each property with ReadProperty.
  defp fetch_bacnet_object_without_rpm(client, destination, object) do
    with {:ok, object_name} <- read_object_name(client, destination, object),
         {:ok, bacnet_object} <- build_bacnet_object(object, object_name),
         properties <- properties_without_rpm(client, destination, object, bacnet_object) do
      {:ok, bacnet_object, properties, :individual}
    end
  end

  defp properties_without_rpm(client, destination, object, bacnet_object) do
    case read_property_list(client, destination, object) do
      {:ok, property_list} ->
        normalize_properties(property_list)

      {:error, _reason} ->
        if is_object(bacnet_object) do
          bacnet_object |> ObjectsUtility.get_properties() |> normalize_properties()
        else
          []
        end
    end
  end

  defp read_object_name(client, destination, object) do
    case client.read_property(destination, object, :object_name, @read_opts) do
      {:ok, name} when is_binary(name) ->
        {:ok, name}

      {:ok, %Encoding{value: name}} when is_binary(name) ->
        {:ok, name}

      _read_object_name ->
        {:ok, default_object_name(object)}
    end
  end

  defp default_object_name(%ObjectIdentifier{type: type, instance: instance}),
    do: "#{type}:#{instance}"

  defp build_bacnet_object(%ObjectIdentifier{} = object, object_name) do
    case ObjectsUtility.cast_properties_to_object(
           object,
           %{object_name: object_name},
           allow_unknown_properties: true
         ) do
      {:ok, bacnet_object} -> {:ok, bacnet_object}
      {:error, :unsupported_object_type} -> {:ok, nil}
      {:error, _reason} = err -> err
    end
  end

  defp read_property_list(client, destination, object) do
    case client.read_property(destination, object, :property_list, @read_opts) do
      {:ok, property_list} ->
        {:ok, unwrap_property_list(property_list)}

      {:error, _err} = error ->
        if Segmentation.fallback_error?(error) do
          read_property_list_indexed(client, destination, object)
        else
          error
        end
    end
  end

  defp read_property_list_indexed(client, destination, object) do
    indexed_opts = Keyword.merge(@read_opts, array_index: 0)

    case client.read_property(destination, object, :property_list, indexed_opts) do
      {:ok, 0} ->
        {:ok, []}

      {:ok, count} when is_integer(count) and count > 0 ->
        props =
          1..count
          |> Task.async_stream(
            fn idx ->
              case client.read_property(
                     destination,
                     object,
                     :property_list,
                     Keyword.merge(@read_opts, array_index: idx)
                   ) do
                {:ok, prop} -> unwrap_property_identifier(prop)
                _read_property_list_index -> nil
              end
            end,
            max_concurrency: 8,
            timeout: :infinity,
            ordered: false
          )
          |> Enum.reduce([], fn
            {:ok, prop}, acc when not is_nil(prop) -> [prop | acc]
            _read_property_list_index, acc -> acc
          end)
          |> Enum.reverse()

        {:ok, props}

      {:error, _reason} = err ->
        err

      _read_property_list_indexed ->
        {:error, :property_list_not_readable}
    end
  end

  defp unwrap_property_list(%BACnetArray{} = array), do: BACnetArray.to_list(array)
  defp unwrap_property_list(list) when is_list(list), do: list
  defp unwrap_property_list(%Encoding{value: value}), do: unwrap_property_list(value)
  defp unwrap_property_list(value), do: [value]

  defp unwrap_property_identifier(%Encoding{value: value}), do: unwrap_property_identifier(value)
  defp unwrap_property_identifier(value), do: value

  defp property_list(bacnet_object) when is_object(bacnet_object) do
    properties =
      bacnet_object
      |> ObjectsUtility.get_properties()
      |> normalize_properties()

    {:ok, properties}
  end

  @doc false
  def normalize_properties(list) when is_list(list) do
    list
    |> Enum.map(&normalize_property/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&valid_property?/1)
    |> Enum.uniq()
  end

  def normalize_properties(_list), do: []

  defp normalize_property(:engineering_units), do: :units
  defp normalize_property(prop) when is_atom(prop), do: prop
  defp normalize_property(prop) when is_integer(prop), do: prop
  defp normalize_property(%{value: val}), do: normalize_property(val)
  defp normalize_property(%ObjectIdentifier{}), do: nil
  defp normalize_property(_engineering_units), do: nil

  defp valid_property?(prop) when is_atom(prop) do
    case Constants.by_name(:property_identifier, prop) do
      {:ok, _prop} -> true
      :error -> false
    end
  end

  defp valid_property?(prop) when is_integer(prop) and prop >= 0, do: true
  defp valid_property?(_prop), do: false

  defp read_all_properties(client, destination, object, properties, :individual) do
    {:ok, read_properties_individually(client, destination, object, properties)}
  end

  defp read_all_properties(client, destination, object, properties, :rpm) do
    results =
      properties
      |> Enum.chunk_every(@chunk_size)
      |> Enum.reduce(%{}, fn chunk, acc ->
        merge_results(acc, read_chunk(client, destination, object, chunk))
      end)

    {:ok, results}
  end

  defp read_chunk(_client, _destination, _object, chunk) when not is_list(chunk), do: %{}

  defp read_chunk(client, destination, object, chunk) do
    rpm_results =
      case client.read_property_multiple(destination, object, chunk, @read_opts) do
        {:ok, results} -> results_map(results)
        {:error, _client} -> %{}
      end

    missing_props = Enum.reject(chunk, fn prop -> Map.has_key?(rpm_results, prop) end)
    missing = read_properties_individually(client, destination, object, missing_props)

    merge_results(rpm_results, missing)
  end

  defp merge_results(left, right)
       when is_map(left) and not is_struct(left) and is_map(right) and not is_struct(right),
       do: Map.merge(left, right)

  defp merge_results(_left, right) when is_map(right) and not is_struct(right), do: right
  defp merge_results(left, _right) when is_map(left) and not is_struct(left), do: left
  defp merge_results(_left, _right), do: %{}

  defp read_properties_individually(_client, _destination, _object, []), do: %{}

  defp read_properties_individually(client, destination, object, properties) do
    properties
    |> Task.async_stream(
      fn prop ->
        case client.read_property(destination, object, prop, @read_opts) do
          {:ok, value} -> {prop, value}
          {:error, _client} -> nil
        end
      end,
      max_concurrency: 8,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.reduce(%{}, fn
      {:ok, {prop, value}}, acc -> Map.put(acc, prop, value)
      _client, acc -> acc
    end)
  end

  defp results_map(%ObjectIdentifier{}), do: %{}

  defp results_map(results) when is_list(results) do
    Enum.reduce(results, %{}, fn
      %{property_identifier: prop, value: value}, acc ->
        Map.put(acc, prop, value)

      {prop, value}, acc ->
        Map.put(acc, prop, value)

      _other, acc ->
        acc
    end)
  end

  defp results_map(results) when is_map(results) and not is_struct(results), do: results

  defp results_map(results) do
    if is_object(results) do
      ObjectsUtility.to_map(results)
    else
      %{}
    end
  end

  defp format_results(properties, results, bacnet_object)
       when is_list(properties) and is_map(results) do
    type_map = properties_type_map(bacnet_object)

    properties
    |> Enum.map(fn property ->
      value = Map.get(results, property)
      display = PropertyDisplay.build(value)
      bac_type = Map.get(type_map, property)

      %{
        property: property,
        property_name: property_name(property),
        value: value,
        value_display: display,
        value_formatted: display.formatted,
        bac_type: bac_type,
        type: property_type(value, display, bac_type),
        writable: writable_property?(bacnet_object, property, results),
        updated_at: DateTime.utc_now()
      }
      |> PropertyEnumeration.enrich_property(bac_type)
      |> Text.sanitize_property_row()
    end)
    |> Enum.sort_by(& &1.property_name)
  end

  defp properties_type_map(bacnet_object) when is_object(bacnet_object) do
    mod = bacnet_object.__struct__

    if function_exported?(mod, :get_properties_type_map, 0) do
      mod.get_properties_type_map()
    else
      %{}
    end
  end

  defp properties_type_map(_bacnet_object), do: %{}

  defp property_type(_value, _display, {:constant, _type}), do: "ENUMERATED"

  defp property_type(nil, _display, :boolean), do: "BOOLEAN"
  defp property_type(nil, _display, :real), do: "REAL"
  defp property_type(nil, _display, :unsigned_integer), do: "INTEGER"
  defp property_type(nil, _display, :signed_integer), do: "INTEGER"
  defp property_type(nil, _display, :double), do: "REAL"
  defp property_type(nil, _display, :string), do: "CHARACTER STRING"
  defp property_type(nil, _display, _bac_type), do: "—"

  defp property_type(_value, %{kind: kind}, _bac_type)
       when kind in [:struct, :priority_array, :array],
       do: "STRUCT"

  defp property_type(value, _display, _bac_type), do: PropertyFormatter.property_type(value)

  defp property_name(property) when is_atom(property),
    do: property |> Atom.to_string() |> String.replace("_", " ")

  defp property_name(property) when is_integer(property) do
    case Constants.by_value(:property_identifier, property) do
      {:ok, name} -> String.replace(Atom.to_string(name), "_", " ")
      :error -> "property #{property}"
    end
  end

  defp property_name(property), do: inspect(property)

  @doc false
  @spec input_object_type?(atom()) :: boolean()
  def input_object_type?(type) when is_atom(type), do: type in @input_object_types
  def input_object_type?(_type), do: false

  @doc false
  @spec sync_input_present_value_writable([map()], map() | nil) :: [map()]
  def sync_input_present_value_writable(properties, object) when is_list(properties) do
    if input_object_summary?(object) do
      enabled = out_of_service_enabled_in_properties?(properties)

      Enum.map(properties, fn
        %{property: :present_value} = prop -> Map.put(prop, :writable, enabled)
        prop -> prop
      end)
    else
      properties
    end
  end

  def sync_input_present_value_writable(properties, _properties), do: properties

  defp writable_property?(_object, property, _results)
       when property in [:object_identifier, :object_name, :object_type, :property_list],
       do: false

  defp writable_property?(object, property, results) when is_object(object) do
    case property do
      :present_value -> present_value_writable?(object, results)
      _object -> ObjectsUtility.property_writable?(object, property)
    end
  end

  defp writable_property?(_object, property, _results)
       when property in [:out_of_service, :description, :relinquish_default],
       do: true

  defp writable_property?(_object, _property, _results), do: false

  defp present_value_writable?(object, results) do
    if input_object_type?(ObjectsUtility.get_object_type(object)) do
      out_of_service_enabled?(object, results)
    else
      ObjectsUtility.property_writable?(object, :present_value)
    end
  end

  defp out_of_service_enabled?(object, results) do
    case Map.get(results, :out_of_service) do
      true -> true
      false -> false
      _object -> Map.get(object, :out_of_service) == true
    end
  end

  defp input_object_summary?(%{type: type}), do: input_object_type?(type)
  defp input_object_summary?(_input_object_summary), do: false

  defp out_of_service_enabled_in_properties?(properties) do
    case Enum.find(properties, &(&1.property == :out_of_service)) do
      %{value: true} -> true
      _properties -> false
    end
  end
end
