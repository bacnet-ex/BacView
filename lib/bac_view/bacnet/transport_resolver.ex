defmodule BacView.BACnet.TransportResolver do
  @moduledoc """
  Resolves the configured BACnet transport module and options for `BacView.BACnet.Stack`.
  """

  alias BacView.BACnet.InterfaceSelection
  alias BacView.Settings

  @transports %{
    "ipv4" => BacView.BACnet.Transport.IPv4,
    "mstp" => BacView.BACnet.Transport.MSTP,
    "bacnet_sc" => BacView.BACnet.Transport.BACnetSC
  }

  @ui_transports (if Application.compile_env(:bacview, :mstp_enabled, true) do
                    ~w(ipv4 mstp)
                  else
                    ~w(ipv4)
                  end)

  @spec resolve() :: {:ok, module(), keyword()} | {:error, term()}
  def resolve() do
    settings = Settings.get()

    case InterfaceSelection.resolve(settings.transport, settings.interface) do
      {:ok, %{interface: interface, options: _options}} ->
        with {:ok, module} <- fetch_module(settings.transport),
             opts <- transport_opts(%{settings | interface: interface}) do
          if module.available?() do
            {:ok, module, opts}
          else
            {:error, {:transport_not_available, settings.transport}}
          end
        end

      {:error, reason, _resolve} ->
        {:error, reason}
    end
  end

  @spec supported_transports() :: [String.t()]
  def supported_transports(), do: @ui_transports

  defp fetch_module(name) when is_binary(name) do
    case Map.fetch(@transports, String.downcase(name)) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_transport, name}}
    end
  end

  defp transport_opts(settings) do
    base = [name: BacView.BACnet.TransportLayer]

    case settings.transport do
      "mstp" ->
        Keyword.merge(base,
          port_name: settings.interface,
          local_address: settings.mstp_local_address,
          baudrate: settings.mstp_baud_rate
        )

      _settings ->
        Keyword.put(base, :local_ip, settings.interface)
    end
  end
end
