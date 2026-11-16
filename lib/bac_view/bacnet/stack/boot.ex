defmodule BacView.BACnet.Stack.Boot do
  @moduledoc false
  use GenServer

  require Logger

  alias BACnet.Stack.Client
  alias BACnet.Stack.Transport.ScTransport.Node, as: SCNode
  alias BacView.BACnet.AlarmEvent
  alias BacView.BACnet.NetworkNumber
  alias BacView.BACnet.Stack
  alias BacView.BACnet.Stack.Runtime
  alias BacView.BACnet.SubscriptionManager
  alias BacView.Settings

  @runtime_id Runtime
  @stack_supervisor Stack
  @check_interval_ms 5_000

  @client BacView.BACnet.ClientStack
  @transport BacView.BACnet.TransportLayer
  @segmentator BacView.BACnet.Segmentator
  @segments_store BacView.BACnet.SegmentsStore

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec running?() :: boolean()
  def running?(), do: GenServer.call(__MODULE__, :running?)

  @spec last_error() :: term() | nil
  def last_error(), do: GenServer.call(__MODULE__, :last_error)

  @spec start_runtime() :: :ok | {:error, term()}
  def start_runtime() do
    GenServer.call(__MODULE__, :start_runtime, 60_000)
  end

  @spec restart() :: :ok | {:error, term()}
  def restart() do
    GenServer.call(__MODULE__, :restart, 60_000)
  end

  @impl true
  def init(_opts) do
    schedule_runtime_check()

    {:ok,
     %{
       error: nil,
       runtime_ref: nil,
       runtime_snapshot: nil,
       sc_link: nil,
       sc_session: nil,
       sc_credentials: nil
     }}
  end

  @impl true
  def handle_call(:running?, _from, state) do
    {:reply, runtime_running?(), state}
  end

  @impl true
  def handle_call(:last_error, _from, state) do
    {:reply, state.error, state}
  end

  def handle_call(:status, _from, state) do
    state = if state.sc_link, do: check_runtime_children(state), else: state
    running? = runtime_running?()
    sc_link = state.sc_link
    ready? = running? and sc_link in [nil, :primary, :failover]

    id =
      case state.sc_credentials do
        {pid, id} -> if pid == Process.whereis(@transport), do: id
        nil -> nil
      end

    {:reply,
     %{
       running?: running?,
       ready?: ready?,
       last_error: state.error,
       sc_link: sc_link,
       sc_credential_id: id
     }, state}
  end

  def handle_call(action, _from, state) when action in [:start_runtime, :restart] do
    state = stop_runtime(state)
    state = start_runtime(state)

    if runtime_running?() do
      snapshot = runtime_snapshot()
      resubscribe_clients()
      state = update_link(%{state | error: nil, runtime_snapshot: snapshot}, snapshot, true)
      {:reply, :ok, state}
    else
      {:reply, {:error, state.error}, state}
    end
  end

  @impl true
  def handle_info(:check_runtime, state) do
    schedule_runtime_check()
    {:noreply, check_runtime_children(state)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{runtime_ref: ref} = state) do
    # Intentional stops (supervisor restart/shutdown) are expected; only unexpected exits warn.
    if reason not in [:normal, :shutdown] and not match?({:shutdown, _}, reason) do
      Logger.warning("BACnet stack runtime stopped: #{inspect(reason)}")
    end

    state = reset_link(state)
    {:noreply, %{state | error: {:runtime_down, reason}}}
  end

  def handle_info({:sc_vmac, pid, vmac}, state) do
    if Process.whereis(@transport) == pid do
      case Settings.persist_sc_vmac(vmac) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Could not store BACnet/SC VMAC: #{reason}")
      end
    end

    {:noreply, state}
  end

  def handle_info({:sc_credentials_applied, pid, id}, state) do
    if Process.whereis(@transport) == pid do
      {:noreply, %{state | sc_credentials: {pid, id}}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp start_runtime(state) do
    case Supervisor.start_child(@stack_supervisor, Runtime.child_spec()) do
      {:ok, pid} ->
        %{state | error: nil, runtime_ref: Process.monitor(pid)}

      {:error, reason} ->
        Logger.warning("BACnet stack failed to start: #{inspect(reason)}")
        %{state | error: reason, runtime_ref: nil, runtime_snapshot: nil}
    end
  end

  defp stop_runtime(state) do
    if is_reference(state.runtime_ref) do
      Process.demonitor(state.runtime_ref, [:flush])
    end

    terminate_runtime_child()
    reset_link(state)
  end

  defp terminate_runtime_child() do
    case Enum.find(
           Supervisor.which_children(@stack_supervisor),
           &match?({@runtime_id, _, _, _}, &1)
         ) do
      {@runtime_id, pid, _terminate_runtime_child, _terminate_runtime_child2} when is_pid(pid) ->
        _terminate_runtime_child = Supervisor.terminate_child(@stack_supervisor, @runtime_id)
        _terminate_runtime_child = Supervisor.delete_child(@stack_supervisor, @runtime_id)
        :ok

      _terminate_runtime_child ->
        :ok
    end
  end

  defp reset_link(state) do
    %{
      state
      | runtime_ref: nil,
        runtime_snapshot: nil,
        sc_link: nil,
        sc_session: nil,
        sc_credentials: nil
    }
  end

  defp check_runtime_children(%{runtime_ref: nil} = state), do: state

  defp check_runtime_children(state) do
    snapshot = runtime_snapshot()
    changed? = snapshot != state.runtime_snapshot

    if changed? and snapshot do
      Logger.info("BACnet stack runtime children changed, resubscribing dependents")
      resubscribe_clients()
    end

    update_link(%{state | runtime_snapshot: snapshot}, snapshot, changed?)
  end

  defp update_link(state, nil, _new_runtime) do
    %{state | sc_session: nil}
  end

  defp update_link(state, snapshot, new_runtime?) do
    case Client.get_transport(snapshot.client) do
      {SCNode, _transport, portal} ->
        update_sc_link(state, portal, SCNode.status(portal))

      {_module, _transport, _portal} ->
        if new_runtime?, do: SubscriptionManager.resubscribe_all_active()
        %{state | sc_link: nil, sc_session: nil, error: nil}
    end
  catch
    :exit, _reason -> state
  end

  defp update_sc_link(state, portal, %{active: role} = status)
       when role in [:primary, :failover] do
    session = {portal, role, Map.fetch!(status, role).connected_at, status.vmac}
    if session != state.sc_session, do: SubscriptionManager.resubscribe_all_active()

    %{state | sc_link: role, sc_session: session, error: nil}
  end

  defp update_sc_link(state, _portal, status) do
    case Enum.find_value([status.primary, status.failover], &(&1 && &1.error)) do
      {:dial_error, :tls, _reason} ->
        %{state | sc_link: :retrying, sc_session: nil, error: :sc_tls_failed}

      nil ->
        %{state | sc_link: :connecting, sc_session: nil, error: nil}

      _reason ->
        %{state | sc_link: :retrying, sc_session: nil, error: :sc_connection_failed}
    end
  end

  defp runtime_snapshot() do
    snapshot = %{
      client: Process.whereis(@client),
      transport: Process.whereis(@transport),
      segmentator: Process.whereis(@segmentator),
      segments_store: Process.whereis(@segments_store)
    }

    if snapshot.client, do: snapshot, else: nil
  end

  defp runtime_running?() do
    Process.whereis(@client) != nil
  end

  defp resubscribe_clients() do
    SubscriptionManager.resubscribe_client()
    AlarmEvent.resubscribe_client()
    NetworkNumber.resubscribe_client()
  end

  defp schedule_runtime_check() do
    Process.send_after(self(), :check_runtime, @check_interval_ms)
  end
end
