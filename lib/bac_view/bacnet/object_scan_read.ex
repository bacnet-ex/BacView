defmodule BacView.BACnet.ObjectScanRead do
  @moduledoc """
  Scan-style object reads: ReadPropertyMultiple with per-property fallback.

  Used during device scan and as a fallback path when full property loads fail
  (segmentation, missing RPM support, etc.). Individual property resolution is
  delegated to `PropertyReader.read_properties_map/4`.

  Cast/validation failures (`invalid_property_value`, `missing_optional_property`,
  etc.) are **not** silently recovered here — they surface as scan errors so the
  UI can list them (and offer skip-mode retry when recoverable).
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.BACnet.Segmentation

  @doc """
  Reads an object via RPM when possible; on segmentation-style / unrecognized-service
  RPM failures falls back to property-list / schema + individual property reads
  (as a raw value map).
  """
  @spec read_object_fallback(term(), ObjectIdentifier.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def read_object_fallback(address, %ObjectIdentifier{} = object, opts) do
    case Client.read_object(address, object, opts) do
      {:ok, obj} ->
        {:ok, obj}

      {:error, :unsupported_object_type} = err ->
        err

      {:error, reason} = err ->
        if Segmentation.rpm_fallback_error?(err) do
          Client.log_read_error(:read_object, address, object, nil, reason, level: :debug)
          PropertyReader.read_properties_map(Client, address, object, opts)
        else
          Client.log_read_error(:read_object, address, object, nil, reason)
          err
        end
    end
  end
end
