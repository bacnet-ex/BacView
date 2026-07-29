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

  # Top-level for cast_read_properties_ack / cast_property_to_value; also in
  # object_opts so ObjectsMacro create/update accepts integer constants.
  @numeric_constant_opts [
    allow_numeric_constants: true,
    object_opts: [allow_numeric_constants: true]
  ]

  @type recovery_mode :: :value | true | :ignore_invalid | :skip_all_and_ignore_invalid

  @recovery_modes [:value, true, :ignore_invalid, :skip_all_and_ignore_invalid]

  @doc false
  @spec recovery_mode?(term()) :: boolean()
  def recovery_mode?(mode), do: mode in @recovery_modes

  @doc false
  @spec property_read_opts(recovery_mode() | nil, ObjectIdentifier.t() | nil) :: keyword()
  def property_read_opts(skip_mode \\ nil, device_obj \\ nil) do
    base =
      case device_obj do
        %ObjectIdentifier{instance: instance} ->
          [
            allow_unknown_properties: :no_unpack,
            ignore_unsupported_object_types: true,
            remote_device_id: instance
          ]

        _other ->
          [allow_unknown_properties: :no_unpack, ignore_unsupported_object_types: true]
      end

    base
    |> Keyword.merge(@numeric_constant_opts)
    |> put_recovery_mode_opts(skip_mode)
  end

  # User-chosen recovery only. Never applied automatically on first failure.
  defp put_recovery_mode_opts(opts, nil), do: opts

  defp put_recovery_mode_opts(opts, :ignore_invalid) do
    Keyword.put(opts, :ignore_invalid_properties, true)
  end

  defp put_recovery_mode_opts(opts, :skip_all_and_ignore_invalid) do
    opts
    |> put_recovery_mode_opts(true)
    |> put_recovery_mode_opts(:ignore_invalid)
  end

  defp put_recovery_mode_opts(opts, mode) when mode in [:value, true] do
    object_opts =
      opts
      |> Keyword.get(:object_opts, [])
      |> Keyword.put(:skip_property_validation_remote_object, mode)

    Keyword.put(opts, :object_opts, object_opts)
  end

  @doc false
  @spec scan_read_opts(ObjectIdentifier.t(), recovery_mode() | nil) :: keyword()
  def scan_read_opts(%ObjectIdentifier{} = device_obj, skip_mode \\ nil) do
    property_read_opts(skip_mode, device_obj)
  end

  @doc false
  @spec device_scan_opts(integer(), ObjectIdentifier.t(), recovery_mode() | nil, keyword()) ::
          keyword()
  def device_scan_opts(device_id, %ObjectIdentifier{} = device_obj, skip_mode \\ nil, extra \\ []) do
    device_id
    |> then(fn id ->
      device_obj
      |> scan_read_opts(skip_mode)
      |> Keyword.put(:remote_device_id, id)
    end)
    |> Keyword.merge(extra)
  end

  @doc """
  Reads all properties for `object` with optional recovery mode and device context.

  Recovery mode is applied on the normal RPM/individual path only when the user
  previously chose it (or the caller passes it); it does **not** force the scan
  fallback path up front and is never auto-selected on first failure.

  Optional `opts`:
  - `:on_property_progress` - `fun.(%{stage: :reading_properties, done: n, total: m})`
    during individual (non-RPM) property streams
  """
  @spec read(
          term(),
          ObjectIdentifier.t(),
          recovery_mode() | nil,
          ObjectIdentifier.t() | nil,
          keyword()
        ) ::
          {:ok, PropertyReader.read_result()} | {:error, term()}
  def read(address, %ObjectIdentifier{} = object, skip_mode, device_obj, opts \\ []) do
    read_via_property_reader(address, object, skip_mode, device_obj, opts)
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
    Segmentation.rpm_fallback_error?({:error, reason}) or
      reason in [:object_unavailable, :property_list_not_readable]
  end

  defp read_via_property_reader(address, object, skip_mode, device_obj, opts) do
    read_opts = merge_progress_opts(property_read_opts(skip_mode, device_obj), opts)

    case PropertyReader.read_all(Client, address, object, read_opts) do
      {:ok, _result} = ok ->
        ok

      {:error, reason} = err ->
        if properties_scan_fallback_on_error?(reason) do
          case read_via_scan_fallback(address, object, device_obj, skip_mode, opts) do
            {:ok, _fallback_result} = fallback_ok -> fallback_ok
            {:error, _fallback_err} -> err
          end
        else
          err
        end
    end
  end

  defp read_via_scan_fallback(address, object, device_obj, skip_mode, opts) do
    fallback_opts =
      device_obj
      |> scan_fallback_read_opts(skip_mode)
      |> merge_progress_opts(opts)

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

  defp merge_progress_opts(read_opts, opts) when is_list(read_opts) and is_list(opts) do
    read_opts
    |> maybe_put_pass_through_opt(opts, :on_property_progress)
    |> maybe_put_pass_through_opt(opts, :remote_device_id)
  end

  defp maybe_put_pass_through_opt(read_opts, opts, key) do
    case Keyword.get(opts, key) do
      nil -> read_opts
      value -> Keyword.put(read_opts, key, value)
    end
  end
end
