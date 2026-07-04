defmodule BacView.BACnet.IAmCollector do
  @moduledoc false

  require Logger

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.BvlcForwardedNPDU
  alias BACnet.Protocol.Services.IAm
  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Client

  @doc """
  Subscribes the caller to the BACnet client, runs `send_fun/0`, then collects
  I-Am responses for `timeout` ms from the caller's mailbox.

  This mirrors `BACnet.Stack.ClientHelper.who_is/3` and ensures the collecting
  process is always registered as a client notification receiver.
  """
  @spec collect_while((-> :ok | {:error, term()}), pos_integer(), keyword()) ::
          {:ok, [{term(), IAm.t()}]} | {:error, term()}
  def collect_while(send_fun, timeout, opts \\ [])

  def collect_while(send_fun, timeout, opts)
      when is_function(send_fun, 0) and is_integer(timeout) and timeout > 0 and is_list(opts) do
    client = Client.stack_client()
    :ok = StackClient.subscribe(client, self())

    try do
      case send_fun.() do
        :ok -> {:ok, collect(timeout, opts)}
        {:error, _send_fun} = err -> err
      end
    after
      StackClient.unsubscribe(client, self())
    end
  end

  @doc """
  Collects I-Am responses for `timeout` ms from the caller's mailbox.

  The caller must already be subscribed to the BACnet stack client.
  Returns a list of `{address, %IAm{}}` tuples, deduplicated by device instance.

  Options:
    * `:on_iam` - optional `(address, IAm.t() -> any)` callback invoked per response
  """
  @spec collect(pos_integer(), keyword()) :: [{term(), IAm.t()}]
  def collect(timeout, opts \\ []) when is_integer(timeout) and timeout > 0 do
    ref = make_ref()
    timer = Process.send_after(self(), {:bacview_iam_collector, :stop, ref}, timeout)
    on_iam = Keyword.get(opts, :on_iam)

    try do
      {acc, messages} = collect_loop(ref, %{}, on_iam, 0)

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

  defp collect_loop(ref, acc, on_iam, messages) do
    receive do
      {:bacnet_client, _reply_ref, apdu, {source, bvlc, _npci}, _client_pid} ->
        collect_loop(ref, ingest_apdu(acc, apdu, source, bvlc, on_iam), on_iam, messages + 1)

      {:bacview_iam_collector, :stop, ^ref} ->
        {acc, messages}

      {:bacnet_transport, _proto, source, {:bvlc, bvlc}, _portal} ->
        Logger.debug(
          "IAmCollector: BVLC message from #{format_address(source)}: #{inspect(bvlc)}"
        )

        collect_loop(ref, acc, on_iam, messages)

      other ->
        Logger.debug("IAmCollector: ignored message #{inspect(other)}")
        collect_loop(ref, acc, on_iam, messages)
    end
  end

  defp ingest_apdu(acc, apdu, source, bvlc, on_iam) do
    case parse_iam(apdu) do
      {:ok, %IAm{device: %{instance: instance}} = iam} ->
        address = device_address(source, bvlc)

        Logger.info(
          "IAmCollector: device #{instance} at #{format_address(address)} " <>
            "(source #{format_address(source)})"
        )

        if on_iam, do: on_iam.(address, iam)

        Map.put(acc, instance, {address, iam})

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

  @spec device_address(term(), term()) :: {term(), term()}
  def device_address(source, bvlc) do
    case bvlc do
      %BvlcForwardedNPDU{originating_ip: ip, originating_port: port} ->
        {ip, port}

      _source ->
        normalize_address(source)
    end
  end

  defp normalize_address({ip, port}) when is_tuple(ip) and is_integer(port), do: {ip, port}
  defp normalize_address({ip, port, _tag}) when is_tuple(ip) and is_integer(port), do: {ip, port}
  defp normalize_address(other), do: other

  defp format_address({a, b, c, d}), do: "#{:inet.ntoa({a, b, c, d})}"
  defp format_address({ip, port}) when is_tuple(ip), do: "#{:inet.ntoa(ip)}:#{port}"
  defp format_address(other), do: inspect(other)
end
