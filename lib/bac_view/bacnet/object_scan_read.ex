defmodule BacView.BACnet.ObjectScanRead do
  @moduledoc """
  Scan-style object reads: ReadPropertyMultiple with per-property fallback.

  Used during device scan and as a fallback path when full property loads fail
  (segmentation, missing RPM support, etc.). Individual property resolution is
  delegated to `PropertyReader.read_properties_map/4`.
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client
  alias BacView.BACnet.Protocol.PropertyReader
  alias BacView.BACnet.Segmentation

  @doc """
  Reads an object via RPM when possible; on segmentation-style errors falls back
  to property-list / schema + individual property reads (as a raw value map).
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
          PropertyReader.read_properties_map(Client, address, object, opts)
        else
          err
        end
    end
  end
end
