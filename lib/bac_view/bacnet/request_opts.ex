defmodule BacView.BACnet.RequestOpts do
  @moduledoc false

  alias BACnet.Protocol.NpciTarget
  alias BacView.BACnet.ApduSize
  alias BacView.BACnet.Discovery
  alias BacView.Settings

  @doc """
  Builds bacstack Client send-related opts for a known BacView device id.

  Opt keys after merge:

  | Key | Meaning |
  |-----|---------|
  | `remote_device_id` | Object cast / remote object metadata (device instance) |
  | `device_id` | Caller alias for the BacView device instance. Not a `Client.send` option. |
  | `npci_id` | Routed `NpciTarget` invoke-id pool key for `Client.send` |
  | `destination` | NPCI destination `NpciTarget` learned from I-Am |
  | `max_apdu` / `max_apdu_length` | Effective APDU size: min(local setting, remote max) |
  | `max_segments` | Local max segments (2/4/8/16/32/64) for request encode and outgoing segmentation |

  Callers should pass the BacView device instance as `:device_id` and/or
  `:remote_device_id` in `base`.
  `:npci_id` copies `:destination` only for a routed remote station whose
  transport address is not shared. Otherwise those devices share one invoke-id
  pool. Sharing is resolved from discovery flags (`shared_destination?` /
  share index), not by scanning all devices on every request.
  """
  @spec for_device(integer(), keyword()) :: keyword()
  def for_device(device_id, base \\ []) when is_integer(device_id) and is_list(base) do
    case Discovery.get_device(device_id) do
      {:ok, device} -> merge_for_device(device_id, device, base)
      :error -> put_apdu_opts(base, nil)
    end
  end

  @doc """
  Merges routing opts when `base` carries `:device_id` or `:remote_device_id`.
  Always injects effective APDU size opts unless already present.
  Injects `:max_segments` when the local setting is a BACnet integer count.
  """
  @spec merge(keyword()) :: keyword()
  def merge(opts) when is_list(opts) do
    case device_id_from(opts) do
      id when is_integer(id) -> for_device(id, opts)
      _other -> put_apdu_opts(opts, nil)
    end
  end

  @doc false
  @spec shared_address?(term()) :: boolean()
  def shared_address?(address), do: Discovery.shared_destination?(address)

  defp merge_for_device(device_id, device, opts) do
    opts
    |> Keyword.put_new(:remote_device_id, device_id)
    |> maybe_put_npci_destination(device)
    |> maybe_put_npci_id(device)
    |> put_apdu_opts(device)
  end

  defp put_apdu_opts(opts, device) do
    opts
    |> put_apdu_size_opts(device)
    |> put_max_segments_opts()
  end

  defp put_apdu_size_opts(opts, device) do
    if Keyword.has_key?(opts, :max_apdu) or Keyword.has_key?(opts, :max_apdu_length) do
      opts
    else
      Keyword.merge(opts, ApduSize.to_opts(device))
    end
  end

  # Client.send requires a positive integer. `:more_than_64` is valid for
  # ConfirmedServiceRequest encode (bacstack default) but not for send opts /
  # Segmentator, so it is left unset.
  defp put_max_segments_opts(opts) do
    if Keyword.has_key?(opts, :max_segments) do
      opts
    else
      case Settings.max_segments() do
        value when is_integer(value) ->
          Keyword.put(opts, :max_segments, value)

        _more_than_64 ->
          opts
      end
    end
  end

  defp maybe_put_npci_destination(opts, %{npci_source: %NpciTarget{} = source}),
    do: Keyword.put(opts, :destination, source)

  defp maybe_put_npci_destination(opts, _device), do: opts

  # Client.send scopes invoke IDs with `:npci_id` (`NpciTarget` or nil), not an
  # integer device instance. A remote broadcast has no station address, so it
  # stays on the transport destination's shared pool.
  defp maybe_put_npci_id(opts, %{npci_source: %NpciTarget{address: address} = source} = device)
       when not is_nil(address) do
    if shared_destination_device?(device) do
      opts
    else
      Keyword.put(opts, :npci_id, source)
    end
  end

  defp maybe_put_npci_id(opts, _device), do: opts

  defp shared_destination_device?(%{shared_destination?: true}), do: true

  defp shared_destination_device?(%{address: address}) when not is_nil(address),
    do: Discovery.shared_destination?(address)

  defp shared_destination_device?(_device), do: false

  defp device_id_from(opts) do
    Keyword.get(opts, :device_id) || Keyword.get(opts, :remote_device_id)
  end
end
