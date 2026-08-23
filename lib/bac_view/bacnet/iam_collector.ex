defmodule BacView.BACnet.IAmCollector do
  @moduledoc false

  require Logger

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.BvlcForwardedNPDU
  alias BACnet.Protocol.NPCI
  alias BACnet.Protocol.NpciTarget
  alias BACnet.Protocol.Services.IAm
  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Address
  alias BacView.BACnet.Client

  @doc """
  Subscribes the caller to the BACnet client, runs `send_fun/0`, then collects
  I-Am responses for `timeout` ms from the caller's mailbox.

  This mirrors `BACnet.Stack.ClientHelper.who_is/3` and ensures the collecting
  process is always registered as a client notification receiver.

  When the BACnet client process is not running (stack not started, transport
  bind failure, etc.), returns `{:error, :stack_not_started}` without raising
  or exiting — that situation is expected and must not crash callers.

  See `collect/2` for options (`:on_iam`, `:max_count`).
  """
  @spec collect_while((-> :ok | {:error, term()}), pos_integer(), keyword()) ::
          {:ok, [{term(), IAm.t()}]} | {:error, term()}
  def collect_while(send_fun, timeout, opts \\ [])

  def collect_while(send_fun, timeout, opts)
      when is_function(send_fun, 0) and is_integer(timeout) and timeout > 0 and is_list(opts) do
    client = Client.stack_client()

    case subscribe_client(client) do
      :ok ->
        try do
          case send_fun.() do
            :ok -> {:ok, collect(timeout, opts)}
            {:error, _send_fun} = err -> err
          end
        after
          unsubscribe_client(client)
        end

      {:error, _reason} = err ->
        err
    end
  end

  @doc """
  Collects I-Am responses for `timeout` ms from the caller's mailbox.

  The caller must already be subscribed to the BACnet stack client.
  Returns a list of `{address, %IAm{}, npci_source, source_address}` tuples,
  deduplicated by device instance. `npci_source` is a `NpciTarget` when the I-Am
  NPCI carried a source target (typical for BACnet routers), otherwise `nil`.
  `source_address` is the originating peer: for BBMD-forwarded frames
  (`BvlcForwardedNPDU`) the originating IP/port, otherwise the UDP/MS/TP
  transport source.

  Options:
    * `:on_iam` - optional
      `(address, IAm.t(), npci_source :: NpciTarget.t() | nil, source_address :: term() -> any)`
      callback invoked per response
    * `:max_count` - optional positive integer. Stop as soon as this many unique
      device instances have been collected, without waiting for the timeout.
  """
  @spec collect(pos_integer(), keyword()) ::
          [{term(), IAm.t(), NpciTarget.t() | nil, term()}]
  def collect(timeout, opts \\ []) when is_integer(timeout) and timeout > 0 do
    ref = make_ref()
    timer = Process.send_after(self(), {:bacview_iam_collector, :stop, ref}, timeout)
    on_iam = Keyword.get(opts, :on_iam)
    max_count = max_count(opts)

    try do
      {acc, messages} = collect_loop(ref, %{}, on_iam, max_count, 0)

      Logger.info(
        "IAmCollector: collected #{map_size(acc)} device(s) from #{messages} BACnet message(s)"
      )

      Map.values(acc)
    after
      Process.cancel_timer(timer)

      receive do
        {:bacview_iam_collector, :stop, ^ref} -> :ok
      after
        0 -> :ok
      end
    end
  end

  defp collect_loop(ref, acc, on_iam, max_count, messages) do
    receive do
      {:bacnet_client, _reply_ref, apdu, {source, bvlc, npci}, _client_pid} ->
        acc = ingest_apdu(acc, apdu, source, bvlc, npci, on_iam)
        messages = messages + 1

        if reached_max?(acc, max_count) do
          {acc, messages}
        else
          collect_loop(ref, acc, on_iam, max_count, messages)
        end

      {:bacview_iam_collector, :stop, ^ref} ->
        {acc, messages}

      {:bacnet_transport, _proto, source, {:bvlc, bvlc}, _portal} ->
        Logger.debug(
          "IAmCollector: BVLC message from #{format_address(source)}: #{inspect(bvlc)}"
        )

        collect_loop(ref, acc, on_iam, max_count, messages)

      other ->
        Logger.debug("IAmCollector: ignored message #{inspect(other)}")
        collect_loop(ref, acc, on_iam, max_count, messages)
    end
  end

  defp max_count(opts) do
    case Keyword.get(opts, :max_count) do
      n when is_integer(n) and n > 0 -> n
      _other -> nil
    end
  end

  defp reached_max?(_acc, nil), do: false
  defp reached_max?(acc, max_count), do: map_size(acc) >= max_count

  defp ingest_apdu(acc, apdu, source, bvlc, npci, on_iam) do
    case parse_iam(apdu) do
      {:ok, %IAm{device: %{instance: instance}} = iam} ->
        address = device_address(source, bvlc)
        npci_source = npci_source_from(npci)
        # Prefer BvlcForwardedNPDU originating peer over the BBMD hop that
        # delivered the frame on the wire.
        source_address = source_address(source, bvlc)

        Logger.info(
          "IAmCollector: device #{instance} at #{format_address(address)} " <>
            "(source #{format_address(source_address)}, " <>
            "npci source #{Address.format_npci_target(npci_source)})"
        )

        if on_iam, do: on_iam.(address, iam, npci_source, source_address)

        Map.put(acc, instance, {address, iam, npci_source, source_address})

      {:error, reason} ->
        Logger.debug("IAmCollector: ignored APDU #{inspect(reason)}")
        acc
    end
  end

  @spec parse_iam(term()) :: {:ok, IAm.t()} | {:error, term()}
  def parse_iam(%IAm{} = iam), do: {:ok, iam}

  def parse_iam(%UnconfirmedServiceRequest{} = apdu) do
    case UnconfirmedServiceRequest.to_service(apdu) do
      {:ok, %IAm{} = iam} -> {:ok, iam}
      _iam -> {:error, :not_i_am}
    end
  end

  def parse_iam(_iam), do: {:error, :not_i_am}

  @doc false
  @spec source_address(term(), term()) :: term()
  def source_address(source, bvlc), do: device_address(source, bvlc)

  @doc false
  @spec device_address(term(), term()) :: term()
  def device_address(source, bvlc) do
    case bvlc do
      %BvlcForwardedNPDU{originating_ip: ip, originating_port: port} ->
        # BBMD Forwarded-NPDU: use the originating device, not the BBMD hop.
        normalize_address({ip, port})

      _bvlc ->
        normalize_address(source)
    end
  end

  @doc false
  @spec npci_source_from(NPCI.t() | term()) :: NpciTarget.t() | nil
  def npci_source_from(%NPCI{source: %NpciTarget{} = source}), do: source
  def npci_source_from(_npci), do: nil

  defp normalize_address(address), do: Address.normalize_destination(address)
  defp format_address(address), do: Address.format_destination(address)

  defp subscribe_client(client) do
    if client_running?(client) do
      :ok = StackClient.subscribe(client, self())
      :ok
    else
      {:error, :stack_not_started}
    end
  catch
    :exit, {:noproc, _client} ->
      {:error, :stack_not_started}
  end

  defp unsubscribe_client(client) do
    if client_running?(client) do
      StackClient.unsubscribe(client, self())
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  # stack_client/0 is the named ClientStack process (atom), not a bare pid.
  defp client_running?(client) when is_atom(client), do: Process.whereis(client) != nil
end
