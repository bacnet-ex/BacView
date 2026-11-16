defmodule BacView.BACnet.StackLifecycle do
  @moduledoc """
  Restarts the BACnet stack runtime and re-wires dependent processes.
  """
  require Logger

  alias BacView.BACnet.Discovery
  alias BacView.BACnet.ForeignRegistration
  alias BacView.BACnet.NetworkNumber
  alias BacView.BACnet.Stack

  alias BacView.Settings

  @spec restart() :: :ok | {:error, term()}
  def restart() do
    settings = Settings.get()
    bbmd = bbmd_registration(settings)

    with :ok <- Discovery.cancel_scan(),
         :ok <- ForeignRegistration.suspend(),
         :ok <- NetworkNumber.clear_learned(),
         :ok <- restart_stack() do
      reregister_bbmd(bbmd)
    end
  end

  defp restart_stack() do
    case Stack.restart() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      Logger.error("Stack restart failed: #{inspect(error)}")
      {:error, error}
  end

  defp reregister_bbmd(nil), do: :ok

  defp reregister_bbmd({host, port, ttl}) do
    case ForeignRegistration.register(host, port, ttl: ttl) do
      :ok -> :ok
      {:error, reason} -> {:error, {:bbmd_reregister_failed, reason}}
    end
  end

  defp bbmd_registration(%{transport: "ipv4", bbmd_host: host, bbmd_port: port, bbmd_ttl: ttl})
       when is_binary(host) and host != "" do
    {host, port, ttl}
  end

  defp bbmd_registration(_bbmd_registration), do: nil
end
