defmodule BacView.BACnet.RequestOpts do
  @moduledoc false

  alias BACnet.Protocol.NpciTarget
  alias BacView.BACnet.Address
  alias BacView.BACnet.Discovery

  @doc """
  Adds BACnet NPCI routing and invoke-id options for routed or shared endpoints.

  Uses `:device_id` or `:remote_device_id` from `opts` to resolve the target device.
  A stored `:npci_source` is mirrored as `:destination` (`NpciTarget`) whenever
  present (learned from the I-Am NPCI source). `:device_id` is set for invoke-id
  management only when the device has an NPCI source and does not share its
  transport destination address with other discovered devices.
  """
  @spec merge(keyword()) :: keyword()
  def merge(opts) when is_list(opts) do
    case device_id_from(opts) do
      id when is_integer(id) -> merge_for_device(id, opts)
      _other -> opts
    end
  end

  @doc false
  @spec shared_address?(term()) :: boolean()
  def shared_address?(address) do
    normalized = Address.normalize_destination(address)

    Enum.count(Discovery.list_devices(), &Address.same_destination?(&1.address, normalized)) > 1
  end

  defp merge_for_device(device_id, opts) do
    case Discovery.get_device(device_id) do
      {:ok, device} ->
        opts
        |> maybe_put_device_id(device_id, device)
        |> maybe_put_npci_destination(device)

      :error ->
        opts
    end
  end

  defp maybe_put_device_id(opts, device_id, %{npci_source: %NpciTarget{}, address: address}) do
    if shared_address?(address) do
      opts
    else
      Keyword.put(opts, :device_id, device_id)
    end
  end

  defp maybe_put_device_id(opts, _device_id, _device), do: opts

  defp maybe_put_npci_destination(opts, %{npci_source: %NpciTarget{} = source}),
    do: Keyword.put(opts, :destination, source)

  defp maybe_put_npci_destination(opts, _device), do: opts

  defp device_id_from(opts) do
    Keyword.get(opts, :device_id) || Keyword.get(opts, :remote_device_id)
  end
end
