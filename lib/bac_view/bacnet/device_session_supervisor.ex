defmodule BacView.BACnet.DeviceSessionSupervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec available?() :: boolean()
  def available?() do
    Process.whereis(BacView.BACnet.DeviceRegistry) != nil and
      Process.whereis(__MODULE__) != nil
  end

  @spec session_pid(integer()) :: pid() | nil
  def session_pid(device_id) do
    if Process.whereis(BacView.BACnet.DeviceRegistry) do
      GenServer.whereis(via(device_id))
    end
  end

  @spec ensure_session(integer()) :: {:ok, pid()} | {:error, term()}
  def ensure_session(device_id) do
    if available?() do
      case session_pid(device_id) do
        nil ->
          spec = {BacView.BACnet.DeviceSession, device_id}

          case DynamicSupervisor.start_child(__MODULE__, spec) do
            {:ok, pid} -> {:ok, pid}
            {:error, {:already_started, pid}} -> {:ok, pid}
            other -> other
          end

        pid ->
          {:ok, pid}
      end
    else
      {:error, :bacnet_unavailable}
    end
  end

  @doc """
  Terminates every running device session.

  Used when the discovered device list is cleared so the next load starts
  from a cold session (no in-memory scan cache).
  """
  @spec stop_all() :: :ok
  def stop_all() do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      _pid ->
        children = DynamicSupervisor.which_children(__MODULE__)

        Enum.each(children, fn
          {_id, pid, :worker, _modules} when is_pid(pid) ->
            _terminate_result = DynamicSupervisor.terminate_child(__MODULE__, pid)

          _other ->
            :ok
        end)

        :ok
    end
  end

  def via(device_id), do: {:via, Registry, {BacView.BACnet.DeviceRegistry, device_id}}

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
