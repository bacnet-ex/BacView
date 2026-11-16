defmodule BacView.BACnet.Transport do
  @moduledoc """
  Transport behaviour for BACnet connectivity.

  Adapters integrate BACnet/IP, MS/TP, and Secure Connect with the client runtime.
  """

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback stack_transport_module() :: module()
  @callback broadcast_address(pid()) :: term()
  @callback available?() :: boolean()
end
