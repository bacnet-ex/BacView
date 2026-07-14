defmodule BacView.BACnet.PropertyLoad do
  @moduledoc """
  Full object property load for the UI (RPM via PropertyReader, with scan fallback).

  Session code resolves skip modes and caches results; this module only performs
  the BACnet reads and formats a PropertyReader result map.

  Always tries PropertyReader (RPM / individual with skip opts) first. Falls back
  to ObjectScanRead only on segmentation-style or object-unavailable errors.
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.BACnet.ObjectScanRead
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.BACnet.Segmentation

  @doc false
  @spec property_read_opts(:value | true | nil, ObjectIdentifier.t() | nil) :: keyword()
  def property_read_opts(skip_mode \\ nil, device_obj \\ nil) do
    base =
      case device_obj do
        %ObjectIdentifier{instance: instance} ->
          [allow_unknown_properties: true, remote_device_id: instance]

        _other ->
          [allow_unknown_properties: true]
      end

    case skip_mode do
      nil ->
        base

      mode when mode in [:value, true] ->
        Keyword.put(base, :object_opts, skip_property_validation_remote_object: mode)
    end
  end

  @doc false
  @spec scan_read_opts(ObjectIdentifier.t(), :value | true | nil) :: keyword()
  def scan_read_opts(%ObjectIdentifier{} = device_obj, skip_mode \\ nil) do
    property_read_opts(skip_mode, device_obj)
  end

  @doc """
  Reads all properties for `object` with optional skip_mode and device context.

  Skip mode is applied via `object_opts` on the normal RPM/individual path; it
  does **not** force the scan fallback path up front.
  """
  @spec read(term(), ObjectIdentifier.t(), :value | true | nil, ObjectIdentifier.t() | nil) ::
          {:ok, PropertyReader.read_result()} | {:error, term()}
  def read(address, %ObjectIdentifier{} = object, skip_mode, device_obj) do
    read_via_property_reader(address, object, skip_mode, device_obj)
  rescue
    exception ->
      {:error, {:property_read_failed, exception}}
  catch
    :exit, reason ->
      {:error, {:property_read_failed, reason}}
  end

  @doc false
  @spec properties_scan_fallback_on_error?(term()) :: boolean()
  def properties_scan_fallback_on_error?(reason) do
    Segmentation.fallback_error?({:error, reason}) or
      reason in [:object_unavailable, :property_list_not_readable]
  end

  defp read_via_property_reader(address, object, skip_mode, device_obj) do
    opts = property_read_opts(skip_mode, device_obj)

    case PropertyReader.read_all(Client, address, object, opts) do
      {:ok, _result} = ok ->
        ok

      {:error, reason} = err ->
        if properties_scan_fallback_on_error?(reason) do
          case read_via_scan_fallback(address, object, device_obj, skip_mode) do
            {:ok, _fallback_result} = fallback_ok -> fallback_ok
            {:error, _fallback_err} -> err
          end
        else
          err
        end
    end
  end

  defp read_via_scan_fallback(address, object, device_obj, skip_mode) do
    fallback_opts = scan_fallback_read_opts(device_obj, skip_mode)

    case ObjectScanRead.read_object_fallback(address, object, fallback_opts) do
      {:ok, obj} ->
        {:ok, PropertyReader.read_result_from_object(object, obj)}

      {:error, _reason} = err ->
        err
    end
  end

  defp scan_fallback_read_opts(%ObjectIdentifier{} = device_obj, skip_mode),
    do: scan_read_opts(device_obj, skip_mode)

  defp scan_fallback_read_opts(device_obj, skip_mode),
    do: property_read_opts(skip_mode, device_obj)
end
