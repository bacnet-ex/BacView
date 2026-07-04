defmodule BacView.BACnet.Transport.BACnetSC do
  @moduledoc """
  Placeholder for future BACnet/SC (WebSocket) transport.

  BACnet/SC requires a secure WebSocket hub connection and hub URI configuration.
  This module documents the intended interface until a full implementation lands.
  """

  @behaviour BacView.BACnet.Transport

  @impl true
  def available?(), do: false

  @impl true
  def stack_transport_module(), do: __MODULE__

  @impl true
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]}
    }
  end

  @impl true
  def broadcast_address(_transport), do: {:error, :not_implemented}

  def start_link(_opts) do
    {:stop, {:not_implemented, :bacnet_sc_transport}}
  end
end
