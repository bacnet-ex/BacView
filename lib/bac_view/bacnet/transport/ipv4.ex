defmodule BacView.BACnet.Transport.IPv4 do
  @moduledoc false
  @behaviour BacView.BACnet.Transport

  alias BACnet.Stack.Transport.IPv4Transport

  @impl true
  def available?(), do: true

  @impl true
  def stack_transport_module(), do: IPv4Transport

  @impl true
  def child_spec(opts) do
    client = Keyword.fetch!(opts, :client)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    IPv4Transport.child_spec(client, transport_opts)
  end

  @impl true
  def broadcast_address(transport) do
    IPv4Transport.get_broadcast_address(transport)
  end
end
