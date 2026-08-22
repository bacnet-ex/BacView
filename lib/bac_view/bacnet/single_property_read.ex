defmodule BacView.BACnet.SinglePropertyRead do
  @moduledoc """
  One-shot ReadProperty by device instance, transport address, or BACnet URI.
  """

  alias BACnet.Protocol.ObjectIdentifier

  alias BacView.BACnet.Address
  alias BacView.BACnet.Client
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.PropertyLoad
  alias BacView.BACnet.Protocol.BacnetUri
  alias BacView.BACnet.RequestOpts
  alias BacView.Settings

  @max_instance 4_194_303

  @type destination ::
          {:device_id, integer()}
          | {:address, {:inet.ip_address(), pos_integer()} | 0..254}

  @type request :: %{
          destination: destination(),
          object: ObjectIdentifier.t(),
          property: atom() | non_neg_integer(),
          array_index: non_neg_integer() | nil
        }

  @type result :: %{
          value: term(),
          destination: term(),
          object: ObjectIdentifier.t(),
          property: atom() | non_neg_integer(),
          array_index: non_neg_integer() | nil
        }

  @spec from_params(map(), keyword()) :: {:ok, result()} | {:error, term()}
  def from_params(params, opts \\ []) when is_map(params) do
    uri = params |> Map.get("uri", "") |> to_string() |> String.trim()

    if uri != "" do
      from_uri(uri, opts)
    else
      from_form(params, opts)
    end
  end

  @spec from_uri(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def from_uri(uri, opts \\ []) when is_binary(uri) do
    this_device_id = Keyword.get(opts, :this_device_id)

    with {:ok, parsed} <- BacnetUri.parse(String.trim(uri)),
         {:ok, device_id} <- BacnetUri.device_instance(parsed, this_device_id),
         {:ok, property} <- BacnetUri.property_for_read(parsed) do
      run(
        %{
          destination: {:device_id, device_id},
          object: parsed.object_identifier,
          property: property,
          array_index: parsed.property_array_index
        },
        opts
      )
    end
  end

  @spec from_form(map(), keyword()) :: {:ok, result()} | {:error, term()}
  def from_form(params, opts \\ []) when is_map(params) do
    with {:ok, destination} <- parse_locator(params, opts),
         {:ok, object} <- parse_object(params),
         {:ok, property} <- parse_property(params, object),
         {:ok, array_index} <- parse_array_index(params) do
      run(
        %{
          destination: destination,
          object: object,
          property: property,
          array_index: array_index
        },
        opts
      )
    end
  end

  @spec run(request(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(request, opts \\ [])

  def run(
        %{
          destination: destination,
          object: %ObjectIdentifier{} = object,
          property: property,
          array_index: array_index
        },
        opts
      )
      when (is_atom(property) or (is_integer(property) and property >= 0)) and
             (is_nil(array_index) or (is_integer(array_index) and array_index >= 0)) do
    client = client(opts)

    with {:ok, wire_dest, read_opts} <- resolve(destination, object, property, array_index) do
      case do_read(client, wire_dest, object, property, read_opts) do
        {:ok, value} ->
          {:ok,
           %{
             value: value,
             destination: wire_dest,
             object: object,
             property: property,
             array_index: array_index
           }}

        {:error, _reason} = err ->
          err
      end
    end
  end

  def run(_request, _opts), do: {:error, :invalid_params}

  defp client(opts) do
    Keyword.get(opts, :client) ||
      Application.get_env(:bacview, :single_property_read_client, Client)
  end

  defp resolve({:address, dest}, object, property, array_index) do
    read_opts = read_opts(nil, object, property, array_index)
    {:ok, dest, read_opts}
  end

  defp resolve({:device_id, device_id}, object, property, array_index)
       when is_integer(device_id) and device_id >= 0 and device_id <= @max_instance do
    case Discovery.resolve_destination(device_id) do
      {:ok, dest} ->
        device_obj = %ObjectIdentifier{type: :device, instance: device_id}
        base = read_opts(device_obj, object, property, array_index)
        {:ok, dest, RequestOpts.for_device(device_id, base)}

      {:error, _reason} = err ->
        err
    end
  end

  defp resolve(_destination, _object, _property, _array_index), do: {:error, :invalid_params}

  defp read_opts(device_obj, _object, _property, array_index) do
    opts = PropertyLoad.property_read_opts(nil, device_obj)

    if is_integer(array_index) do
      Keyword.put(opts, :array_index, array_index)
    else
      opts
    end
  end

  defp do_read(client, dest, object, property, read_opts) do
    case client.read_property(dest, object, property, read_opts) do
      {:ok, _value} = ok ->
        ok

      {:error, :unsupported_object_type} ->
        client.read_property(dest, object, property, Keyword.put(read_opts, :raw, true))

      {:error, _reason} = err ->
        err
    end
  end

  defp parse_locator(params, opts) do
    case Map.get(params, "locator", "device_id") do
      "address" -> parse_address_locator(params, opts)
      "device_id" -> parse_device_id_locator(params)
      _locator -> {:error, :invalid_locator}
    end
  end

  defp parse_device_id_locator(params) do
    raw = params |> Map.get("device_id", "") |> to_string() |> String.trim()

    case Integer.parse(raw) do
      {id, ""} when id >= 0 and id <= @max_instance ->
        {:ok, {:device_id, id}}

      {_id, ""} ->
        {:error, :invalid_device}

      _empty when raw == "" ->
        {:error, :missing_device_id}

      _other ->
        {:error, :invalid_device}
    end
  end

  defp parse_address_locator(params, opts) do
    raw = params |> Map.get("address", "") |> to_string() |> String.trim()
    transport = Keyword.get(opts, :transport) || Settings.transport()

    if raw == "" do
      {:error, :missing_address}
    else
      case Address.parse_transport_destination(raw, transport) do
        {:ok, dest} -> {:ok, {:address, dest}}
        {:error, _reason} = err -> err
      end
    end
  end

  defp parse_object(params) do
    type_str = params |> Map.get("object_type", "") |> to_string() |> String.trim()
    instance_str = params |> Map.get("instance", "") |> to_string() |> String.trim()

    cond do
      type_str == "" ->
        {:error, :missing_object_type}

      instance_str == "" ->
        {:error, :missing_instance}

      String.contains?(type_str, "/") or String.contains?(instance_str, "/") ->
        {:error, :invalid_object}

      true ->
        case BacnetUri.parse("bacnet://0/" <> type_str <> "," <> instance_str) do
          {:ok, uri} -> {:ok, uri.object_identifier}
          {:error, _reason} = err -> err
        end
    end
  end

  defp parse_property(params, object) do
    prop_str = params |> Map.get("property", "") |> to_string() |> String.trim()

    if prop_str == "" do
      default_property(object)
    else
      parse_property_string(prop_str, object)
    end
  end

  defp default_property(%ObjectIdentifier{type: :file}), do: {:error, :file_content_uri}
  defp default_property(_object), do: {:ok, :present_value}

  defp parse_property_string(prop_str, object) do
    if String.contains?(prop_str, "/") do
      {:error, :invalid_property}
    else
      type_str = object_type_segment(object)

      uri =
        "bacnet://0/" <> type_str <> "," <> Integer.to_string(object.instance) <> "/" <> prop_str

      case BacnetUri.parse(uri) do
        {:ok, parsed} -> BacnetUri.property_for_read(parsed)
        {:error, _reason} = err -> err
      end
    end
  end

  defp object_type_segment(%ObjectIdentifier{type: type}) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp object_type_segment(%ObjectIdentifier{type: type}) when is_integer(type) do
    Integer.to_string(type)
  end

  defp parse_array_index(params) do
    raw = params |> Map.get("array_index", "") |> to_string() |> String.trim()

    case raw do
      "" ->
        {:ok, nil}

      _raw ->
        case Integer.parse(raw) do
          {index, ""} when index >= 0 -> {:ok, index}
          _other -> {:error, :invalid_index}
        end
    end
  end
end
