defmodule BacView.BACnet.SerialPorts do
  @moduledoc false

  @type option :: %{value: String.t(), label: String.t()}

  @spec list() :: [option()]
  def list() do
    if Code.ensure_loaded?(Circuits.UART) do
      Circuits.UART.enumerate()
      |> port_names_from_enumerate()
      |> Enum.map(fn port -> %{value: port, label: port} end)
      |> Enum.sort_by(& &1.label, :asc)
    else
      []
    end
  end

  defp port_names_from_enumerate(ports) when is_map(ports), do: Map.keys(ports)

  @spec available?() :: boolean()
  def available?(), do: Code.ensure_loaded?(Circuits.UART)
end
