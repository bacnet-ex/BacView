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
    unless available?() do
      {:error, :bacnet_unavailable}
    else
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
    end
  end

  def via(device_id), do: {:via, Registry, {BacView.BACnet.DeviceRegistry, device_id}}

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
