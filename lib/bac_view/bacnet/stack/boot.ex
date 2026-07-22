defmodule BacView.BACnet.Stack.Boot do
  @moduledoc false
  use GenServer

  require Logger

  alias BacView.BACnet.AlarmEvent
  alias BacView.BACnet.Stack
  alias BacView.BACnet.Stack.Runtime
  alias BacView.BACnet.SubscriptionManager

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
    {:ok, %{error: nil, runtime_ref: nil, runtime_snapshot: nil}}
  end

  @impl true
  def handle_call(:running?, _from, state) do
    {:reply, runtime_running?(), state}
  end

  @impl true
  def handle_call(:last_error, _from, state) do
    {:reply, state.error, state}
  end

  @impl true
  def handle_call(:start_runtime, _from, state) do
    state = stop_runtime(state)
    state = start_runtime(state)

    if runtime_running?() do
      resubscribe_dependents()
      {:reply, :ok, %{state | error: nil, runtime_snapshot: runtime_snapshot()}}
    else
      {:reply, {:error, state.error}, state}
    end
  end

  @impl true
  def handle_call(:restart, _from, state) do
    state = stop_runtime(state)
    state = start_runtime(state)

    if runtime_running?() do
      resubscribe_dependents()
      {:reply, :ok, %{state | error: nil, runtime_snapshot: runtime_snapshot()}}
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

    {:noreply, %{state | error: {:runtime_down, reason}, runtime_ref: nil, runtime_snapshot: nil}}
  end

  @impl true
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
    %{state | runtime_ref: nil, runtime_snapshot: nil}
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

  defp check_runtime_children(%{runtime_ref: nil} = state) do
    %{state | runtime_snapshot: nil}
  end

  defp check_runtime_children(%{runtime_ref: ref} = state) when is_reference(ref) do
    case runtime_snapshot() do
      nil ->
        if state.runtime_snapshot != nil do
          Logger.warning("BACnet stack runtime children unavailable")
        end

        %{state | runtime_snapshot: nil}

      current when current != state.runtime_snapshot ->
        if state.runtime_snapshot != nil do
          Logger.info("BACnet stack runtime children changed, resubscribing dependents")
          resubscribe_dependents()
        end

        %{state | runtime_snapshot: current, error: nil}

      _current ->
        state
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

  defp resubscribe_dependents() do
    SubscriptionManager.resubscribe_client()
    AlarmEvent.resubscribe_client()
    BacView.BACnet.NetworkNumber.resubscribe_client()
    SubscriptionManager.resubscribe_all_active()
  end

  defp schedule_runtime_check() do
    Process.send_after(self(), :check_runtime, @check_interval_ms)
  end
end
