defmodule BacView.BACnet.Stack do
  @moduledoc """
  Supervises BACnet stack boot and the optional runtime process tree.
  """
  use Supervisor

  alias BacView.BACnet.Stack.Boot

  @client BacView.BACnet.ClientStack
  @transport BacView.BACnet.TransportLayer

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec client() :: GenServer.server()
  def client(), do: @client

  @spec transport() :: GenServer.server()
  def transport(), do: @transport

  @spec status() :: %{running?: boolean(), last_error: term() | nil}
  def status() do
    %{
      running?: running?(),
      last_error: last_error()
    }
  end

  @spec running?() :: boolean()
  def running?() do
    case Process.whereis(Boot) do
      nil -> false
      pid -> GenServer.call(pid, :running?)
    end
  end

  @spec last_error() :: term() | nil
  def last_error() do
    case Process.whereis(Boot) do
      nil -> nil
      pid -> GenServer.call(pid, :last_error)
    end
  end

  @spec restart() :: :ok | {:error, term()}
  def restart() do
    case Process.whereis(Boot) do
      nil -> {:error, :stack_not_started}
      _pid -> Boot.restart()
    end
  end

  @impl true
  def init(_opts) do
    Supervisor.init([Boot], strategy: :one_for_one)
  end
end
