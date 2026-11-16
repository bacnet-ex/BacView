defmodule BacView.BACnet.Transport.BACnetSC do
  @moduledoc false
  @behaviour BacView.BACnet.Transport

  alias BACnet.Stack.Transport.ScTransport.Node, as: SCNode
  alias BacView.BACnet.SCCredentials
  alias BacView.BACnet.Stack.Boot
  alias BacView.Settings

  @impl true
  def available?(), do: Code.ensure_loaded?(SCNode)

  @impl true
  def stack_transport_module(), do: SCNode

  @impl true
  def child_spec(opts) do
    client = Keyword.fetch!(opts, :client)
    transport_opts = Keyword.fetch!(opts, :transport_opts)

    %{id: __MODULE__, start: {__MODULE__, :start_link, [client, transport_opts]}}
  end

  @impl true
  def broadcast_address(transport), do: SCNode.get_broadcast_address(transport)

  @doc false
  @spec start_link(GenServer.server(), keyword()) :: GenServer.on_start()
  def start_link(client, opts) do
    boot = Process.whereis(Boot)

    with {:ok, credentials, id} <- SCCredentials.load(),
         {:ok, identity} <- Settings.ensure_sc_identity(),
         node_opts =
           Keyword.merge(opts,
             credentials: credentials,
             device_uuid: identity.uuid,
             vmac: identity.vmac,
             status_receiver: boot
           ),
         {:ok, pid} <- SCNode.open(client, node_opts) do
      if boot, do: send(boot, {:sc_credentials_applied, pid, id})
      {:ok, pid}
    end
  end
end
