defmodule BacView.BACnet.Protocol.BacnetUri do
  @moduledoc """
  Thin BacView wrapper around bacstack `BACnet.Protocol.BACnetURI` (Annex Q.8).
  """

  alias BACnet.Protocol.BACnetURI
  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.ObjectIdentifier

  require Constants

  @max_instance Constants.macro_by_name(:asn1, :max_instance_and_property_id)

  @spec parse(String.t()) :: {:ok, BACnetURI.t()} | {:error, term()}
  def parse(uri) when is_binary(uri), do: BACnetURI.parse(uri)

  @spec encode(BACnetURI.t()) :: {:ok, String.t()} | {:error, term()}
  def encode(%BACnetURI{} = uri), do: BACnetURI.encode(uri)

  @spec valid_str?(String.t()) :: boolean()
  def valid_str?(uri) when is_binary(uri), do: BACnetURI.valid_str?(uri)

  @doc """
  Encodes an object-level BACnet URI (device instance + object, no property).

  Uses numeric object-type identifiers, matching `BACnetURI.encode/1`.
  """
  @spec encode_object(non_neg_integer(), ObjectIdentifier.t()) ::
          {:ok, String.t()} | {:error, term()}
  def encode_object(device_instance, %ObjectIdentifier{} = object)
      when is_integer(device_instance) and device_instance >= 0 and
             device_instance <= @max_instance do
    if ObjectIdentifier.valid?(object) do
      case object_type_to_string(object.type) do
        {:ok, type_str} ->
          {:ok,
           "bacnet://" <>
             Integer.to_string(device_instance) <>
             "/" <> type_str <> "," <> Integer.to_string(object.instance)}

        {:error, _reason} = err ->
          err
      end
    else
      {:error, :invalid_data}
    end
  end

  def encode_object(_device_instance, _object), do: {:error, :invalid_data}

  @doc """
  Encodes a property-level BACnet URI (device + object + numeric property).
  """
  @spec encode_property(
          non_neg_integer(),
          ObjectIdentifier.t(),
          atom() | non_neg_integer()
        ) :: {:ok, String.t()} | {:error, term()}
  def encode_property(device_instance, %ObjectIdentifier{} = object, property) do
    with {:ok, object_uri} <- encode_object(device_instance, object),
         {:ok, prop_str} <- property_to_string(property) do
      {:ok, object_uri <> "/" <> prop_str}
    end
  end

  @doc """
  Property to use for ReadProperty. File objects with an omitted property refer
  to file contents (AtomicReadFile), not ReadProperty.
  """
  @spec property_for_read(BACnetURI.t()) ::
          {:ok, atom() | non_neg_integer()} | {:error, :file_content_uri}
  def property_for_read(%BACnetURI{
        property_identifier: nil,
        object_identifier: %ObjectIdentifier{type: :file}
      }) do
    {:error, :file_content_uri}
  end

  def property_for_read(%BACnetURI{property_identifier: property})
      when not is_nil(property) do
    {:ok, property}
  end

  def property_for_read(%BACnetURI{}), do: {:ok, :present_value}

  @spec device_instance(BACnetURI.t(), integer() | nil) ::
          {:ok, integer()} | {:error, :this_device_unknown | :invalid_device}
  def device_instance(%BACnetURI{device_identifier: nil}, this_device_id)
      when is_integer(this_device_id) and this_device_id >= 0 do
    {:ok, this_device_id}
  end

  def device_instance(%BACnetURI{device_identifier: nil}, _this_device_id) do
    {:error, :this_device_unknown}
  end

  def device_instance(
        %BACnetURI{device_identifier: %ObjectIdentifier{type: :device, instance: instance}},
        _this_device_id
      )
      when is_integer(instance) and instance >= 0 do
    {:ok, instance}
  end

  def device_instance(_uri, _this_device_id), do: {:error, :invalid_device}

  @spec object_type_options() :: [String.t()]
  def object_type_options(), do: identifier_options(:object_type)

  @spec property_identifier_options() :: [String.t()]
  def property_identifier_options(), do: identifier_options(:property_identifier)

  defp property_to_string(property) when is_atom(property) do
    case Constants.by_name(:property_identifier, property) do
      {:ok, num} -> {:ok, Integer.to_string(num)}
      :error -> {:error, :invalid_data}
    end
  end

  defp property_to_string(property) when is_integer(property) and property >= 0 do
    {:ok, Integer.to_string(property)}
  end

  defp property_to_string(_property), do: {:error, :invalid_data}

  defp object_type_to_string(type) when is_atom(type) do
    case Constants.by_name(:object_type, type) do
      {:ok, num} -> {:ok, Integer.to_string(num)}
      :error -> {:error, :invalid_data}
    end
  end

  defp object_type_to_string(type) when is_integer(type) and type >= 0 do
    {:ok, Integer.to_string(type)}
  end

  defp object_type_to_string(_type), do: {:error, :invalid_data}

  defp identifier_options(category) do
    case Map.get(Constants.get_typespecs(), category) do
      {names, _values, _doc} when is_list(names) ->
        names
        |> Enum.map(&hyphenate_atom/1)
        |> Enum.sort()

      _category ->
        []
    end
  end

  defp hyphenate_atom(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", "-")
  end
end
