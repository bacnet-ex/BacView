defmodule BacView.BACnet.Transport.MSTP do
  @moduledoc false
  @behaviour BacView.BACnet.Transport

  @impl true
  def available?() do
    Code.ensure_loaded?(Circuits.UART) and
      Code.ensure_loaded?(BACnet.Stack.Transport.MstpTransport)
  end

  @impl true
  def stack_transport_module() do
    BACnet.Stack.Transport.MstpTransport
  end

  @impl true
  def child_spec(opts) do
    client = Keyword.fetch!(opts, :client)
    transport_opts = Keyword.get(opts, :transport_opts, [])
    stack_module = stack_transport_module()

    if available?() do
      do_child_spec(stack_module, client, transport_opts)
    else
      raise ArgumentError, unavailable_error_msg()
    end
  end

  # Workaround to Elixir warnings
  defp do_child_spec(mod, client, transport_opts), do: mod.child_spec(client, transport_opts)

  @impl true
  def broadcast_address(transport) do
    if available?() do
      do_broadcast_address(stack_transport_module(), transport)
    else
      raise ArgumentError, unavailable_error_msg()
    end
  end

  # Workaround to Elixir warnings
  defp do_broadcast_address(mod, transport),
    do: mod.get_broadcast_address(transport)

  defp unavailable_error_msg(),
    do: "The MS/TP transport is not available - make sure circuits_uart is available"
end
