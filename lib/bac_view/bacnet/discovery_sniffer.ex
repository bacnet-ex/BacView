defmodule BacView.BACnet.DiscoverySniffer do
  @moduledoc """
  Legacy GenServer-based I-Am sniffer.

  Network discovery uses `BacView.BACnet.IAmCollector.collect_while/3` instead so the
  scanning process subscribes directly to the bacstack client (same approach as
  `BACnet.Stack.ClientHelper.who_is/3`).
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.Services.IAm
  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Address
  alias BacView.BACnet.Client
  alias BacView.BACnet.IAmCollector

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Arms the sniffer, runs `send_fun/0` in the caller process, then returns collected
  `{address, IAm}` tuples.

  The collection timer starts only after `send_fun/0` succeeds so the full timeout is
  available for I-Am responses (important for BBMD registration and IP-range scans).
  """
  @spec collect_while((-> :ok | {:error, term()}), non_neg_integer(), keyword()) ::
          {:ok, [{term(), IAm.t()}]} | {:error, term()}
  def collect_while(send_fun, timeout, opts \\ [])

  def collect_while(send_fun, timeout, opts)
      when is_function(send_fun, 0) and is_integer(timeout) and timeout > 0 and is_list(opts) do
    on_iam = Keyword.get(opts, :on_iam)

    case GenServer.call(__MODULE__, {:arm, on_iam}) do
      ref when is_reference(ref) ->
        case send_fun.() do
          :ok ->
            :ok = GenServer.call(__MODULE__, {:start_collect, ref, timeout})

            case GenServer.call(__MODULE__, {:await, ref}, timeout + 5_000) do
              {:ok, responses} -> {:ok, responses}
              {:error, _send_fun} = err -> err
            end

          {:error, _send_fun} = err ->
            GenServer.cast(__MODULE__, {:disarm, ref})
            err
        end

      {:error, _send_fun} = err ->
        err
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %{active: nil, client: Client.stack_client(), client_mon_ref: nil},
     {:continue, :subscribe_client}}
  end

  @impl true
  def handle_continue(:subscribe_client, state) do
    {:noreply, ensure_client_subscription(state)}
  end

  @impl true
  def handle_call({:arm, on_iam}, _from, %{active: nil} = state) do
    state = ensure_client_subscription(state)
    ref = make_ref()

    {:reply, ref,
     %{
       state
       | active: %{
           ref: ref,
           timer: nil,
           await_from: nil,
           on_iam: on_iam,
           acc: %{},
           messages: 0
         }
     }}
  end

  def handle_call({:arm, _on_iam}, _from, state) do
    {:reply, {:error, :already_collecting}, state}
  end

  def handle_call({:start_collect, ref, timeout}, _from, %{active: %{ref: ref}} = state) do
    timer = Process.send_after(self(), {:collect_timeout, ref}, timeout)
    {:reply, :ok, put_in(state.active.timer, timer)}
  end

  def handle_call({:start_collect, _ref, _timeout}, _from, state) do
    {:reply, {:error, :not_collecting}, state}
  end

  def handle_call({:await, ref}, from, %{active: %{ref: ref}} = state) do
    {:noreply, put_in(state.active.await_from, from)}
  end

  def handle_call({:await, _ref}, _from, state) do
    {:reply, {:error, :not_collecting}, state}
  end

  @impl true
  def handle_cast({:disarm, ref}, %{active: %{ref: ref}} = state) do
    if state.active.timer, do: Process.cancel_timer(state.active.timer)
    {:noreply, %{state | active: nil}}
  end

  def handle_cast({:disarm, _ref}, state), do: {:noreply, state}

  @impl true
  def handle_info(
        {:bacnet_client, _ref, apdu, {source, bvlc, npci}, _client_pid},
        %{active: active} = state
      )
      when not is_nil(active) do
    {:noreply, ingest_apdu(state, apdu, source, bvlc, npci)}
  end

  def handle_info({:bacnet_client, _ref, apdu, {source, bvlc, _npci}, _client_pid}, state) do
    track_idle_iam(apdu, source, bvlc)
    {:noreply, state}
  end

  def handle_info({:collect_timeout, ref}, %{active: %{ref: ref} = active} = state) do
    reply_await({:ok, Map.values(active.acc)}, active)

    Logger.info(
      "DiscoverySniffer: timed out with #{map_size(active.acc)} device(s), #{active.messages} BACnet message(s)"
    )

    {:noreply, %{state | active: nil}}
  end

  def handle_info({:collect_timeout, _ref}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{client_mon_ref: ref} = state) do
    Logger.warning("DiscoverySniffer: BACnet client restarted, will re-subscribe on next scan")
    {:noreply, %{state | client_mon_ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp ingest_apdu(%{active: active} = state, apdu, source, bvlc, npci) do
    active = %{active | messages: active.messages + 1}

    case IAmCollector.parse_iam(apdu) do
      {:ok, %IAm{device: %{instance: instance}} = iam} ->
        address = IAmCollector.device_address(source, bvlc)
        npci_source = IAmCollector.npci_source_from(npci)
        source_address = IAmCollector.source_address(source, bvlc)

        Logger.info("DiscoverySniffer: I-Am device #{instance} at #{format_address(address)}")

        if on_iam = active.on_iam, do: on_iam.(address, iam, npci_source, source_address)

        %{
          state
          | active: %{
              active
              | acc: Map.put(active.acc, instance, {address, iam, npci_source, source_address})
            }
        }

      {:error, reason} ->
        Logger.debug(
          "DiscoverySniffer: bacnet_client APDU not parsed as I-Am: #{inspect(reason)}"
        )

        %{state | active: active}
    end
  end

  defp reply_await(reply, %{timer: timer, await_from: from}) do
    if timer, do: Process.cancel_timer(timer)
    if from, do: GenServer.reply(from, reply)
  end

  defp track_idle_iam(apdu, source, bvlc) do
    case IAmCollector.parse_iam(apdu) do
      {:ok, %IAm{device: %{instance: instance}} = _iam} ->
        address = IAmCollector.device_address(source, bvlc)

        Logger.warning(
          "DiscoverySniffer: I-Am device #{instance} at #{format_address(address)} arrived outside active collection window"
        )

      _apdu ->
        :ok
    end
  end

  defp ensure_client_subscription(%{client_mon_ref: ref} = state) when is_reference(ref) do
    state
  end

  defp ensure_client_subscription(state) do
    client = state.client

    if Process.whereis(client) do
      :ok = StackClient.subscribe(client, self())
      ref = Process.monitor(client)
      Logger.debug("DiscoverySniffer subscribed to #{inspect(client)}")
      %{state | client_mon_ref: ref}
    else
      Logger.warning("DiscoverySniffer: BACnet client #{inspect(client)} is not running")
      state
    end
  end

  defp format_address(address), do: Address.format_destination(address)
end
