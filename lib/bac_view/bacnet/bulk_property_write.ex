defmodule BacView.BACnet.BulkPropertyWrite do
  @moduledoc """
  Writes one property value to many objects of a device.

  The property list is the scalar properties shared by the selected object
  types. Objects are written one after another. Each result is reported to
  the caller so the UI can show a BACnet error per object.
  """

  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectsUtility
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Protocol.BinaryPV
  alias BacView.BACnet.Protocol.PropertyWriter

  @scalar_primitives [
    :string,
    :boolean,
    :real,
    :double,
    :unsigned_integer,
    :signed_integer,
    :octet_string,
    :character_string,
    :enumerated,
    :integer
  ]

  @summary_properties [
    :present_value,
    :object_name,
    :description,
    :out_of_service,
    :units,
    :event_state
  ]

  @skipped_properties MapSet.new([
                        :object_identifier,
                        :object_type,
                        :object_list,
                        :property_list,
                        :object_instance
                      ])

  @type write_job :: {map(), term()}

  @doc """
  Scalar properties that every schema-backed object type in `objects` can carry.

  Object types without a bacstack schema do not narrow the list. When none of
  the types have a schema, the list is empty.
  """
  @spec candidate_properties([map()]) :: [atom()]
  def candidate_properties(objects) when is_list(objects) do
    sets =
      objects
      |> Enum.map(&Map.get(&1, :type))
      |> Enum.uniq()
      |> Enum.flat_map(fn type ->
        case writable_scalars(type) do
          nil -> []
          set -> [set]
        end
      end)

    case sets do
      [] ->
        []

      [first | rest] ->
        rest
        |> Enum.reduce(first, &MapSet.intersection/2)
        |> MapSet.to_list()
        |> Enum.sort()
    end
  end

  @doc """
  Parses `text` into the BACnet value for `property` on `object`.
  """
  @spec parse_value(atom(), String.t(), map()) :: {:ok, term()} | {:error, atom()}
  def parse_value(property, text, object)
      when is_atom(property) and is_binary(text) and is_map(object) do
    trimmed = String.trim(text)

    cond do
      property == :present_value and nil_token?(trimmed) ->
        {:ok, nil}

      trimmed == "" ->
        {:error, :empty_value}

      true ->
        case property_type(object, property) do
          nil -> parse_untyped(trimmed, property)
          bac_type -> parse_typed(bac_type, trimmed, property, object)
        end
    end
  end

  @doc """
  Runs `jobs` sequentially and sends progress to `parent`.

  Messages:

    * `{:bulk_property_write_row, %{type, instance, status, reason}}`
    * `{:bulk_property_write_done, %{ok, failed}}`

  `status` is `:writing`, `:ok`, or `:error`. `reason` is set only for `:error`.

  With `:bulk_property_write_sync` the writes run in the caller and the results
  are returned as `{:sync, results}` instead of messages. `:bulk_property_write_fun`
  replaces `DeviceSession.write_property/5`.
  """
  @spec start(pid(), integer(), atom(), [write_job()], 1..16 | nil) ::
          :async | {:sync, [map()]}
  def start(parent, device_id, property, jobs, priority)
      when is_pid(parent) and is_integer(device_id) and is_atom(property) and is_list(jobs) do
    if Application.get_env(:bacview, :bulk_property_write_sync, false) do
      {:sync, Enum.map(jobs, &perform_job(device_id, property, priority, &1))}
    else
      Task.start(fn -> run(parent, device_id, property, jobs, priority) end)
      :async
    end
  end

  @doc false
  @spec run(pid(), integer(), atom(), [write_job()], 1..16 | nil) :: :ok
  def run(parent, device_id, property, jobs, priority) do
    {ok, failed} =
      Enum.reduce(jobs, {0, 0}, fn job, {ok_acc, failed_acc} ->
        {object, _value} = job
        send_row(parent, object, :writing)
        result = perform_job(device_id, property, priority, job)
        send(parent, {:bulk_property_write_row, result})

        case result.status do
          :ok -> {ok_acc + 1, failed_acc}
          :error -> {ok_acc, failed_acc + 1}
        end
      end)

    send(parent, {:bulk_property_write_done, %{ok: ok, failed: failed}})
    :ok
  end

  @doc false
  @spec property_type(map(), atom()) :: term()
  def property_type(object, property) when is_map(object) and is_atom(property) do
    case schema_module(Map.get(object, :type)) do
      nil -> nil
      mod -> Map.get(mod.get_properties_type_map(), property)
    end
  end

  defp writable_scalars(type) when is_atom(type) do
    case schema_module(type) do
      nil ->
        nil

      mod ->
        readonly = MapSet.new(mod.get_readonly_properties())
        type_map = mod.get_properties_type_map()

        type_map
        |> Enum.flat_map(fn {name, bac_type} ->
          if writable_scalar?(name, bac_type, readonly), do: [name], else: []
        end)
        |> MapSet.new()
    end
  end

  defp writable_scalars(_type), do: nil

  defp writable_scalar?(name, bac_type, readonly) do
    not MapSet.member?(@skipped_properties, name) and
      not MapSet.member?(readonly, name) and
      text_writable?(bac_type)
  end

  defp text_writable?(type) when type in @scalar_primitives, do: true
  defp text_writable?({:constant, name}) when is_atom(name), do: true
  defp text_writable?({:in_list, values}) when is_list(values), do: true

  defp text_writable?({:in_range, min, max}) when is_integer(min) and is_integer(max), do: true

  defp text_writable?(_type), do: false

  defp schema_module(type) when is_atom(type) do
    case ObjectsUtility.get_object_type_mappings()[type] do
      mod when is_atom(mod) ->
        case Code.ensure_loaded(mod) do
          {:module, ^mod} ->
            if function_exported?(mod, :get_properties_type_map, 0) and
                 function_exported?(mod, :get_readonly_properties, 0) do
              mod
            end

          _load_error ->
            nil
        end

      _missing ->
        nil
    end
  end

  defp schema_module(_type), do: nil

  defp parse_typed({:constant, enum_type}, text, _property, _object) when is_atom(enum_type),
    do: parse_constant(text, enum_type)

  defp parse_typed({:in_list, values}, text, _property, _object) when is_list(values),
    do: parse_in_list(text, values)

  defp parse_typed({:in_range, min, max}, text, _property, _object)
       when is_integer(min) and is_integer(max),
       do: parse_in_range(text, min, max)

  defp parse_typed(:boolean, text, property, object), do: parse_boolean(text, object, property)
  defp parse_typed(:real, text, _property, _object), do: parse_real(text)
  defp parse_typed(:double, text, _property, _object), do: parse_real(text)

  defp parse_typed(:unsigned_integer, text, _property, _object),
    do: parse_integer(text, :unsigned)

  defp parse_typed(:signed_integer, text, _property, _object), do: parse_integer(text, :signed)
  defp parse_typed(:integer, text, _property, _object), do: parse_integer(text, :signed)
  defp parse_typed(:enumerated, text, _property, _object), do: parse_enumerated(text)
  defp parse_typed(:string, text, _property, _object), do: {:ok, text}
  defp parse_typed(:character_string, text, _property, _object), do: {:ok, text}
  defp parse_typed(:octet_string, text, _property, _object), do: {:ok, text}
  defp parse_typed(_bac_type, _text, _property, _object), do: {:error, :unsupported_property}

  defp parse_untyped(text, property) do
    cond do
      property == :present_value and nil_token?(text) ->
        {:ok, nil}

      boolean_word?(text) ->
        parse_boolean(text, %{}, property)

      true ->
        case parse_whole(text) do
          {:ok, integer} ->
            {:ok, integer}

          :error ->
            case parse_real(text) do
              {:ok, float} -> {:ok, float}
              {:error, :invalid_number} -> {:ok, text}
            end
        end
    end
  end

  defp parse_boolean(text, object, property) do
    down = String.downcase(text)

    cond do
      down in ["true", "1", "on", "yes", "ja", "wahr"] ->
        {:ok, true}

      down in ["false", "0", "off", "no", "nein", "falsch"] ->
        {:ok, false}

      binary_value_property?(object, property) and active_text?(down, object) ->
        {:ok, true}

      binary_value_property?(object, property) and inactive_text?(down, object) ->
        {:ok, false}

      true ->
        {:error, :invalid_boolean}
    end
  end

  defp boolean_word?(text) do
    String.downcase(text) in [
      "true",
      "false",
      "on",
      "off",
      "yes",
      "no",
      "ja",
      "nein",
      "wahr",
      "falsch"
    ]
  end

  defp binary_value_property?(object, property) do
    BinaryPV.binary_object?(object) and BinaryPV.value_property?(property)
  end

  defp active_text?(down, object) do
    down == "active" or down == normalized_state_text(object, :active_text)
  end

  defp inactive_text?(down, object) do
    down == "inactive" or down == normalized_state_text(object, :inactive_text)
  end

  defp normalized_state_text(object, key) do
    case Map.get(object, key) do
      text when is_binary(text) ->
        text |> String.trim() |> String.downcase()

      _missing ->
        nil
    end
  end

  defp parse_constant(text, enum_type) do
    case Integer.parse(text) do
      {integer, ""} when integer >= 0 ->
        {:ok, integer}

      {_negative, ""} ->
        {:error, :invalid_enum}

      _other ->
        parse_constant_name(text, enum_type)
    end
  end

  defp parse_constant_name(text, enum_type) do
    case existing_atom(normalize_token(text)) do
      nil ->
        {:error, :invalid_enum}

      atom ->
        case Constants.by_name(enum_type, atom) do
          {:ok, int} when is_integer(int) -> {:ok, atom}
          _error -> {:error, :invalid_enum}
        end
    end
  rescue
    ArgumentError -> {:error, :invalid_enum}
  end

  defp parse_in_list(text, values) do
    case existing_atom(normalize_token(text)) do
      nil ->
        {:error, :invalid_enum}

      atom ->
        if atom in values, do: {:ok, atom}, else: {:error, :invalid_enum}
    end
  end

  defp parse_in_range(text, min, max) do
    case parse_whole(text) do
      {:ok, integer} when integer >= min and integer <= max -> {:ok, integer}
      {:ok, _outside} -> {:error, :out_of_range}
      :error -> {:error, :invalid_number}
    end
  end

  defp parse_enumerated(text) do
    case Integer.parse(text) do
      {integer, ""} when integer >= 0 ->
        {:ok, integer}

      _other ->
        case existing_atom(normalize_token(text)) do
          nil -> {:error, :invalid_enum}
          atom -> {:ok, atom}
        end
    end
  end

  defp parse_integer(text, sign) do
    case parse_whole(text) do
      {:ok, integer} when sign == :unsigned and integer >= 0 -> {:ok, integer}
      {:ok, integer} when sign == :signed -> {:ok, integer}
      {:ok, _negative} -> {:error, :invalid_number}
      :error -> {:error, :invalid_number}
    end
  end

  defp parse_real(text) do
    normalized = normalize_decimal(text)

    case Float.parse(normalized) do
      {float, ""} -> {:ok, float}
      _other -> {:error, :invalid_number}
    end
  end

  defp parse_whole(text) do
    normalized = normalize_decimal(text)

    case Integer.parse(normalized) do
      {integer, ""} ->
        {:ok, integer}

      _other ->
        case Float.parse(normalized) do
          {float, ""} ->
            integer = trunc(float)
            if integer == float, do: {:ok, integer}, else: :error

          _float ->
            :error
        end
    end
  end

  defp normalize_decimal(text) do
    if String.contains?(text, ",") and not String.contains?(text, ".") do
      String.replace(text, ",", ".")
    else
      text
    end
  end

  defp normalize_token(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[\s\-]+/u, "_")
  end

  defp nil_token?(text) do
    String.downcase(text) in ["null", "nil", "none", "-", "relinquish", "reset"]
  end

  defp existing_atom(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  defp perform_job(device_id, property, priority, {object, value}) do
    case write_object(device_id, object, property, value, priority) do
      :ok ->
        maybe_publish(device_id, object, property, value)

        %{
          type: object.type,
          instance: object.instance,
          status: :ok,
          reason: nil
        }

      {:error, reason} ->
        %{
          type: object.type,
          instance: object.instance,
          status: :error,
          reason: reason
        }
    end
  end

  defp write_object(device_id, object, property, value, priority) do
    object_id = %ObjectIdentifier{type: object.type, instance: object.instance}

    opts =
      PropertyWriter.write_opts(object, property, priority || PropertyWriter.default_priority())

    try do
      case writer().(device_id, object_id, property, value, opts) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, other}
      end
    rescue
      exception -> {:error, exception}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp writer() do
    Application.get_env(:bacview, :bulk_property_write_fun, &DeviceSession.write_property/5)
  end

  defp maybe_publish(_device_id, _object, _property, nil), do: :ok

  defp maybe_publish(device_id, object, property, value)
       when property in @summary_properties do
    object_id = %ObjectIdentifier{type: object.type, instance: object.instance}
    DeviceSession.publish_property_update(device_id, object_id, property, value)
  end

  defp maybe_publish(_device_id, _object, _property, _value), do: :ok

  defp send_row(parent, object, status, reason \\ nil) do
    payload = %{
      type: object.type,
      instance: object.instance,
      status: status,
      reason: reason
    }

    send(parent, {:bulk_property_write_row, payload})
  end
end
