defmodule BacView.BACnet.ObjectScanRead do
  @moduledoc """
  Scan-style object reads: ReadPropertyMultiple with per-property fallback.

  Used during device scan and as a fallback path when full property loads fail
  (segmentation, missing RPM support, etc.). Overlaps intentionally with
  PropertyReader's non-RPM path; a later pass may dedupe those (see follow-up 5).
  """

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.BACnet.Segmentation

  @doc """
  Reads an object via RPM when possible; on segmentation-style errors falls back
  to property-list / schema + individual property reads.
  """
  @spec read_object_fallback(term(), ObjectIdentifier.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def read_object_fallback(address, %ObjectIdentifier{} = object, opts) do
    case Client.read_object(address, object, opts) do
      {:ok, obj} ->
        {:ok, obj}

      {:error, :unsupported_object_type} = err ->
        err

      {:error, _reason} = err ->
        if Segmentation.fallback_error?(err) do
          read_properties_for_scan(address, object, opts)
        else
          err
        end
    end
  end

  # Fallback for devices that do not support segmentation: read the property list
  # (indexed when the full array is too large), then read each listed property
  # individually. The resulting plain map is sufficient for summarize_object/1 and
  # hierarchy building (for Structured View subordinate lists etc.).
  defp read_properties_for_scan(address, %ObjectIdentifier{} = object_id, opts) do
    read_opts =
      opts
      |> Keyword.take([:allow_unknown_properties, :remote_device_id])
      |> maybe_merge_object_opts(opts)

    case read_property_list_for_scan(address, object_id, read_opts) do
      {:ok, property_list} ->
        props = PropertyReader.skip_heavy_properties(property_list, object_id)
        read_scanned_properties(address, object_id, props, read_opts)

      {:error, _reason} ->
        read_properties_for_scan_from_schema(address, object_id, read_opts)
    end
  end

  defp read_properties_for_scan_from_schema(address, object_id, read_opts) do
    case PropertyReader.schema_properties(object_id) do
      {:ok, schema_props} ->
        props = PropertyReader.skip_heavy_properties(schema_props, object_id)
        read_scanned_properties(address, object_id, props, read_opts)

      {:error, _reason} = err ->
        err
    end
  end

  defp read_scanned_properties(address, object_id, props, read_opts) do
    {result, _failures} =
      props
      |> Task.async_stream(
        fn prop ->
          case PropertyReader.read_property_value(Client, address, object_id, prop, read_opts) do
            {:ok, value} -> {:ok, {prop, value}}
            {:error, reason} -> {:error, {prop, reason}}
          end
        end,
        max_concurrency: PropertyReader.scan_property_read_concurrency(),
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce({%{}, []}, fn
        {:ok, {:ok, {prop, value}}}, {acc, failed} ->
          {Map.put(acc, prop, value), failed}

        {:ok, {:error, {prop, reason}}}, {acc, failed} ->
          {acc, [{prop, reason} | failed]}

        _other, {acc, failed} ->
          {acc, failed}
      end)

    {:ok, result}
  end

  defp read_property_list_for_scan(address, object_id, read_opts) do
    case PropertyReader.read_property_value(
           Client,
           address,
           object_id,
           :property_list,
           read_opts
         ) do
      {:ok, property_list} ->
        normalized = PropertyReader.normalize_properties(unwrap_property_list(property_list))
        {:ok, normalized}

      {:error, _reason} ->
        read_property_list_indexed_for_scan(address, object_id, read_opts)
    end
  end

  defp read_property_list_indexed_for_scan(address, object_id, read_opts) do
    length_opts = Keyword.put(read_opts, :array_index, 0)

    case PropertyReader.read_property_value(
           Client,
           address,
           object_id,
           :property_list,
           length_opts
         ) do
      {:ok, 0} ->
        {:ok, []}

      {:ok, count} when is_integer(count) and count > 0 ->
        props =
          1..count
          |> Task.async_stream(
            fn idx ->
              case PropertyReader.read_property_value(
                     Client,
                     address,
                     object_id,
                     :property_list,
                     Keyword.merge(read_opts, array_index: idx)
                   ) do
                {:ok, prop} ->
                  prop

                {:error, _reason} ->
                  nil
              end
            end,
            max_concurrency: 8,
            timeout: :infinity,
            ordered: false
          )
          |> Enum.reduce([], fn
            {:ok, prop}, acc when not is_nil(prop) ->
              [prop | acc]

            {:exit, _reason}, acc ->
              acc

            _other, acc ->
              acc
          end)
          |> Enum.reverse()
          |> PropertyReader.normalize_properties()

        {:ok, props}

      {:error, _reason} = err ->
        err

      _other ->
        {:error, :property_list_not_readable}
    end
  end

  defp unwrap_property_list(%BACnetArray{} = array), do: BACnetArray.to_list(array)
  defp unwrap_property_list(list) when is_list(list), do: list
  defp unwrap_property_list(%Encoding{value: value}), do: unwrap_property_list(value)
  defp unwrap_property_list(value), do: [value]

  defp maybe_merge_object_opts(read_opts, opts) do
    case Keyword.get(opts, :object_opts) do
      object_opts when is_list(object_opts) -> Keyword.put(read_opts, :object_opts, object_opts)
      _other -> read_opts
    end
  end
end
