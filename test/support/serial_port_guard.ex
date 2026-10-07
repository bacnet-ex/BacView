defmodule BacView.Test.SerialPortGuard do
  @moduledoc false

  alias BacView.BACnet.InterfaceSelection

  @doc """
  Runs `fun` while the MS/TP port selected for `"ttyS0"` cannot be opened again.

  A present, accessible serial port is held with an exclusive lock. A missing
  port or a permission error already makes stack startup fail, so no lock is
  taken then.
  """
  @spec with_locked_port((-> term())) :: term()
  def with_locked_port(fun) when is_function(fun, 0) do
    uart = lock_selected_port()

    try do
      fun.()
    after
      release(uart)
    end
  end

  defp lock_selected_port() do
    case InterfaceSelection.resolve("mstp", "ttyS0") do
      {:ok, %{interface: port}} -> open_exclusive(port)
      {:error, _reason, _meta} -> nil
    end
  end

  defp open_exclusive(port) do
    case Circuits.UART.start_link() do
      {:ok, pid} ->
        case Circuits.UART.open(pid, port, active: false, speed: 9600) do
          :ok ->
            pid

          {:error, _reason} ->
            _stop_result = Circuits.UART.stop(pid)
            nil
        end

      {:error, _reason} ->
        nil
    end
  end

  defp release(nil), do: :ok

  defp release(pid) when is_pid(pid) do
    _close_result = Circuits.UART.close(pid)
    _stop_result = Circuits.UART.stop(pid)
    :ok
  end
end
