defmodule BacView.BACnet.TransportResolverTest do
  use ExUnit.Case, async: false

  alias BACnet.Stack.Transport.IPv4Transport
  alias BacView.BACnet.Transport.IPv4
  alias BacView.BACnet.TransportResolver
  alias BacView.Settings

  setup do
    on_exit(fn ->
      path = Application.get_env(:bacview, :runtime_settings_path)
      if path, do: File.rm(path)

      {:ok, _} =
        Settings.update(
          transport: "ipv4",
          interface: first_ipv4_interface(),
          device_id: Settings.defaults().device_id,
          network_number: Settings.defaults().network_number,
          mstp_local_address: Settings.defaults().mstp_local_address,
          mstp_baud_rate: Settings.defaults().mstp_baud_rate
        )
    end)

    {:ok, _} =
      Settings.update(
        transport: "ipv4",
        interface: first_ipv4_interface()
      )

    :ok
  end

  test "resolves ipv4 transport" do
    assert {:ok, BacView.BACnet.Transport.IPv4, opts} = TransportResolver.resolve()
    assert opts[:name] == BacView.BACnet.TransportLayer
    assert is_binary(opts[:local_ip])
  end

  test "ipv4 transport exposes bacstack module for client wiring" do
    assert IPv4.stack_transport_module() == IPv4Transport
    assert function_exported?(IPv4, :stack_transport_module, 0)
  end

  test "mstp transport availability follows circuits_uart" do
    if Code.ensure_loaded?(Circuits.UART) and
         Code.ensure_loaded?(BACnet.Stack.Transport.MstpTransport) do
      assert BacView.BACnet.Transport.MSTP.available?()
    else
      refute BacView.BACnet.Transport.MSTP.available?()
    end
  end

  defp first_ipv4_interface do
    case Settings.interface_options("ipv4") do
      [%{value: value} | _] -> value
      _ -> "lo"
    end
  end
end
