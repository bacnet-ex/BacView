defmodule BacView.BACnet.Transport do
  @moduledoc """
  Transport behaviour for BACnet connectivity.

  UDP/IP (`:ipv4`) and MS/TP (`:mstp`) are implemented today. BACnet/SC WebSocket (`:bacnet_sc`) is stubbed
  for a future phase — selecting it at startup returns a clear error.
  """

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback stack_transport_module() :: module()
  @callback broadcast_address(pid()) :: term()
  @callback available?() :: boolean()
end
