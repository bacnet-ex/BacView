defmodule BacView.BACnet.RequestOpts do
  @moduledoc false

  alias BACnet.Protocol.NpciTarget
  alias BacView.BACnet.Discovery

  @doc """
  Builds bacstack Client send-related opts for a known BacView device id.

  Opt keys after merge:

  | Key | Meaning |
  |-----|---------|
  | `remote_device_id` | Object cast / remote object metadata (device instance) |
  | `device_id` | bacstack **invoke-id** partition key (only when routed and destination is unique) |
  | `destination` | NPCI destination `NpciTarget` learned from I-Am |

  Callers should pass the BacView device instance as `:device_id` and/or
  `:remote_device_id` in `base` (aliases accepted for one transition window).
  Sharing is resolved from discovery flags (`shared_destination?` / share index),
  not by scanning all devices on every request.
  """
  @spec for_device(integer(), keyword()) :: keyword()
  def for_device(device_id, base \\ []) when is_integer(device_id) and is_list(base) do
    case Discovery.get_device(device_id) do
      {:ok, device} -> merge_for_device(device_id, device, base)
      :error -> base
    end
  end

  @doc """
  Merges routing opts when `base` carries `:device_id` or `:remote_device_id`.
  """
  @spec merge(keyword()) :: keyword()
  def merge(opts) when is_list(opts) do
    case device_id_from(opts) do
      id when is_integer(id) -> for_device(id, opts)
      _other -> opts
    end
  end

  @doc false
  @spec shared_address?(term()) :: boolean()
  def shared_address?(address), do: Discovery.shared_destination?(address)

  defp merge_for_device(device_id, device, opts) do
    opts
    |> Keyword.put_new(:remote_device_id, device_id)
    |> maybe_put_npci_destination(device)
    |> maybe_put_invoke_device_id(device_id, device)
  end

  defp maybe_put_npci_destination(opts, %{npci_source: %NpciTarget{} = source}),
    do: Keyword.put(opts, :destination, source)

  defp maybe_put_npci_destination(opts, _device), do: opts

  defp maybe_put_invoke_device_id(opts, device_id, %{npci_source: %NpciTarget{}} = device) do
    if shared_destination_device?(device) do
      opts
    else
      Keyword.put(opts, :device_id, device_id)
    end
  end

  defp maybe_put_invoke_device_id(opts, _device_id, _device), do: opts

  defp shared_destination_device?(%{shared_destination?: true}), do: true

  defp shared_destination_device?(%{address: address}) when not is_nil(address),
    do: Discovery.shared_destination?(address)

  defp shared_destination_device?(_device), do: false

  defp device_id_from(opts) do
    Keyword.get(opts, :device_id) || Keyword.get(opts, :remote_device_id)
  end
end
