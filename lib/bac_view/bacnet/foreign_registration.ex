defmodule BacView.BACnet.ForeignRegistration do
  @moduledoc """
  Manages Foreign Device Registration (FDR) with a remote BBMD.

  When registered, Who-Is scans are distributed through the BBMD so devices on
  remote BACnet/IP networks become discoverable.
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.Services.WhoIs
  alias BACnet.Stack.ForeignDevice
  alias BacView.BACnet.Address
  alias BacView.BACnet.Stack
  alias BacView.PubSub

  @topic "bbmd:updates"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec status() :: map()
  def status() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :status)
    else
      disabled_status()
    end
  end

  @spec registered?() :: boolean()
  def registered?() do
    match?(%{registration_status: :registered}, status())
  end

  @spec foreign_device() :: pid() | nil
  def foreign_device() do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, :foreign_device), else: nil
  end

  @spec register(String.t(), pos_integer(), keyword()) :: :ok | {:error, term()}
  def register(host, port \\ Address.default_bbmd_port(), opts \\ []) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:register, host, port, opts}, 30_000)
    else
      {:error, :bacnet_not_started}
    end
  end

  @spec unregister() :: :ok
  def unregister() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :unregister, 30_000)
    else
      :ok
    end
  end

  @spec scan_route() :: :local | :bbmd
  def scan_route() do
    if Process.whereis(__MODULE__) == nil do
      :local
    else
      GenServer.call(__MODULE__, :scan_route)
    end
  end

  @spec who_is(non_neg_integer(), keyword()) ::
          {:ok, [term()]} | {:error, term()} | :use_local
  def who_is(timeout, opts) do
    if Process.whereis(__MODULE__) == nil do
      :use_local
    else
      GenServer.call(__MODULE__, {:who_is, timeout, opts}, who_is_call_timeout(timeout))
    end
  end

  @doc """
  Sends a Who-Is broadcast without collecting I-Am responses.

  Returns `:use_local` when no BBMD route is active (caller should broadcast locally).
  """
  @spec broadcast_who_is(keyword()) :: :ok | {:error, term()} | :use_local
  def broadcast_who_is(opts \\ []) do
    if Process.whereis(__MODULE__) == nil do
      :use_local
    else
      GenServer.call(__MODULE__, {:broadcast_who_is, opts}, 30_000)
    end
  end

  @doc false
  @spec route(map(), map()) :: :local | :bbmd | :bbmd_required
  def route(state, settings) do
    cond do
      bbmd_active?(state) -> :bbmd
      bbmd_configured?(settings) -> :bbmd_required
      true -> :local
    end
  end

  @impl true
  def init(_opts) do
    settings = BacView.Settings.get()

    state = %{
      fd_pid: nil,
      monitor_ref: nil,
      bbmd: nil,
      ttl: settings.bbmd_ttl,
      registration_status: :disabled,
      last_error: nil
    }

    if settings.bbmd_host not in [nil, ""] and stack_ready?() do
      case do_register(state, settings.bbmd_host, settings.bbmd_port, settings.bbmd_ttl) do
        {:ok, new_state} ->
          {:ok, new_state}

        {:error, reason} ->
          new_state = %{state | last_error: reason}
          broadcast_status(new_state)
          {:ok, new_state}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, status_map(state), state}
  end

  @impl true
  def handle_call(:foreign_device, _from, state) do
    {:reply, state.fd_pid, state}
  end

  @impl true
  def handle_call(:scan_route, _from, state) do
    route =
      case route(state, BacView.Settings.get()) do
        :bbmd -> :bbmd
        :bbmd_required -> :bbmd
        :local -> :local
      end

    {:reply, route, state}
  end

  @impl true
  def handle_call({:who_is, timeout, opts}, _from, state) do
    {result, new_state} = perform_who_is(state, timeout, opts)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:broadcast_who_is, opts}, _from, state) do
    {result, new_state} = perform_broadcast_who_is(state, opts)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:register, host, port, opts}, _from, state) do
    ttl = Keyword.get(opts, :ttl, BacView.Settings.get().bbmd_ttl)

    case do_register(state, host, port, ttl) do
      {:ok, new_state} ->
        {:ok, _status} = BacView.Settings.update(bbmd_host: host, bbmd_port: port, bbmd_ttl: ttl)
        {:reply, :ok, new_state}

      {:error, reason} = err ->
        new_state = %{state | last_error: reason}
        broadcast_status(new_state)
        {:reply, err, new_state}
    end
  end

  @impl true
  def handle_call(:unregister, _from, state) do
    {:ok, _status} =
      BacView.Settings.update(bbmd_host: nil, bbmd_port: Address.default_bbmd_port())

    new_state =
      state
      |> Map.put(:bbmd, nil)
      |> Map.put(:last_error, nil)
      |> stop_foreign_device()

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{monitor_ref: ref} = state) do
    new_state =
      Map.put(
        %{state | fd_pid: nil, monitor_ref: nil, registration_status: :disabled},
        :last_error,
        {:foreign_device_down, reason}
      )

    broadcast_status(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll_registration, state) do
    {new_state, changed?} = refresh_registration_status(state)

    if changed?, do: broadcast_status(new_state)
    schedule_poll(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp do_register(state, host, port, ttl) do
    with {:ok, ip} <- Address.parse_host(host),
         {:ok, port} <- Address.parse_port(port),
         {:ok, ttl} <- validate_ttl(ttl) do
      # Stop any existing ForeignDevice before starting a new one. Starting first
      # would register the new entry and then delete it when the old process shuts
      # down (ForeignDevice.stop/1 + terminate/2 both send Delete-FDT-Entry).
      state = stop_foreign_device(state)

      case start_foreign_device({ip, port}, ttl) do
        {:ok, fd_pid} ->
          ref = Process.monitor(fd_pid)

          new_state = %{
            state
            | fd_pid: fd_pid,
              monitor_ref: ref,
              bbmd: {ip, port},
              ttl: ttl,
              registration_status: ForeignDevice.get_status(fd_pid),
              last_error: nil
          }

          schedule_poll(new_state)
          broadcast_status(new_state)
          {:ok, new_state}

        {:error, _state} = err ->
          err
      end
    end
  end

  defp start_foreign_device(bbmd, ttl) do
    opts = [
      bbmd: bbmd,
      client: Stack.client(),
      ttl: ttl,
      reply_rfd: true
    ]

    case ForeignDevice.start_link(opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _bbmd} = err -> err
    end
  end

  defp stop_foreign_device(%{fd_pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid), do: ForeignDevice.stop(pid)
    demonitor(state)
  end

  defp stop_foreign_device(state), do: demonitor(state)

  defp demonitor(%{monitor_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    new_state = %{state | fd_pid: nil, monitor_ref: nil, registration_status: :disabled}
    broadcast_status(new_state)
    new_state
  end

  defp demonitor(state), do: state

  defp validate_ttl(ttl) when is_integer(ttl) and ttl > 0, do: {:ok, ttl}
  defp validate_ttl(_ttl), do: {:error, :invalid_ttl}

  defp status_map(state) do
    registration_status =
      cond do
        is_nil(state.fd_pid) -> :disabled
        Process.alive?(state.fd_pid) -> ForeignDevice.get_status(state.fd_pid)
        true -> :disabled
      end

    {bbmd_host, bbmd_port} = active_bbmd_endpoint(state)

    %{
      enabled: not is_nil(bbmd_host),
      registration_status: registration_status,
      bbmd: state.bbmd,
      bbmd_host: bbmd_host,
      bbmd_port: bbmd_port,
      ttl: state.ttl,
      last_error: state.last_error
    }
  end

  defp active_bbmd_endpoint(%{fd_pid: pid, bbmd: {ip, port}}) when is_pid(pid) do
    if Process.alive?(pid) do
      {Address.format_ip(ip), port}
    else
      {nil, nil}
    end
  end

  defp active_bbmd_endpoint(_pid), do: {nil, nil}

  defp broadcast_status(state) do
    Phoenix.PubSub.broadcast(PubSub, @topic, {:bbmd_updated, status_map(state)})
  end

  defp refresh_registration_status(state) do
    if state.fd_pid && Process.alive?(state.fd_pid) do
      status = ForeignDevice.get_status(state.fd_pid)
      new_state = %{state | registration_status: status}
      {new_state, status != state.registration_status}
    else
      new_state = %{state | registration_status: :disabled}
      {new_state, state.registration_status != :disabled}
    end
  end

  defp schedule_poll(%{fd_pid: pid} = state) when is_pid(pid) do
    interval =
      case state.registration_status do
        status when status in [:waiting_for_ack, :uninitialized] -> 1_000
        :registered -> 5_000
        _pid -> nil
      end

    if interval, do: Process.send_after(self(), :poll_registration, interval)
  end

  defp schedule_poll(_state), do: :ok

  defp stack_ready?() do
    Process.whereis(Stack.client()) != nil
  end

  defp perform_broadcast_who_is(state, opts) do
    settings = BacView.Settings.get()

    case ensure_foreign_device(state, settings) do
      {:ok, fd_pid, new_state} ->
        Logger.info(
          "Who-Is via BBMD (Distribute-Broadcast-To-Network) → #{format_bbmd(new_state.bbmd)}"
        )

        {:ok, apdu} = build_who_is_apdu(opts)
        result = ForeignDevice.distribute_broadcast(fd_pid, apdu, distribute_opts(opts))

        {result, new_state}

      :use_local ->
        {:use_local, state}

      {:error, reason} ->
        Logger.warning("Who-Is via BBMD failed: #{inspect(reason)}")
        new_state = %{state | last_error: reason}
        broadcast_status(new_state)
        {{:error, reason}, new_state}
    end
  end

  defp perform_who_is(state, timeout, opts) do
    settings = BacView.Settings.get()

    case ensure_foreign_device(state, settings) do
      {:ok, fd_pid, new_state} ->
        Logger.info(
          "Who-Is via BBMD (Distribute-Broadcast-To-Network) → #{format_bbmd(new_state.bbmd)}"
        )

        result =
          case ForeignDevice.send_whois(fd_pid, timeout, opts) do
            {:ok, responses} -> {:ok, responses}
            {:error, _state} = err -> err
          end

        {result, new_state}

      :use_local ->
        Logger.debug("Who-Is via local broadcast")
        {:use_local, state}

      {:error, reason} ->
        Logger.warning("Who-Is via BBMD failed: #{inspect(reason)}")
        new_state = %{state | last_error: reason}
        broadcast_status(new_state)
        {{:error, reason}, new_state}
    end
  end

  defp ensure_foreign_device(state, settings) do
    cond do
      bbmd_active?(state) ->
        {:ok, state.fd_pid, state}

      bbmd_configured?(settings) ->
        case do_register(state, settings.bbmd_host, settings.bbmd_port, settings.bbmd_ttl) do
          {:ok, new_state} -> {:ok, new_state.fd_pid, new_state}
          {:error, reason} -> {:error, {:bbmd_registration_failed, reason}}
        end

      true ->
        :use_local
    end
  end

  defp bbmd_active?(%{fd_pid: pid, bbmd: bbmd}) when is_pid(pid) and not is_nil(bbmd) do
    Process.alive?(pid)
  end

  defp bbmd_active?(_bbmd), do: false

  defp bbmd_configured?(settings) do
    settings.bbmd_host not in [nil, ""]
  end

  defp format_bbmd({ip, port}), do: "#{Address.format_ip(ip)}:#{port}"
  defp format_bbmd(_ip), do: "unknown"

  defp build_who_is_apdu(opts) do
    WhoIs.to_apdu(
      %WhoIs{
        device_id_low_limit: opts[:low_limit],
        device_id_high_limit: opts[:high_limit]
      },
      []
    )
  end

  defp distribute_opts(opts) do
    opts
    |> Keyword.drop([:low_limit, :high_limit, :timeout, :max])
    |> Keyword.put_new(:receive_timeout, 250)
  end

  defp who_is_call_timeout(timeout), do: trunc(timeout * 2) + 10_000

  defp disabled_status() do
    settings = BacView.Settings.get()

    %{
      enabled: false,
      registration_status: :disabled,
      bbmd: nil,
      bbmd_host: settings.bbmd_host,
      bbmd_port: settings.bbmd_port,
      ttl: settings.bbmd_ttl,
      last_error: nil
    }
  end
end
