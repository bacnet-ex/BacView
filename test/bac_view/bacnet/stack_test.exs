defmodule BacView.BACnet.StackTest do
  use ExUnit.Case, async: false

  alias BacView.BACnet.Stack
  alias BacView.BACnet.Stack.Boot
  alias BacView.Settings

  setup do
    on_exit(fn ->
      path = Application.get_env(:bacview, :runtime_settings_path)
      if path, do: File.rm(path)

      {:ok, _} =
        Settings.update(
          transport: "ipv4",
          interface: first_ipv4_interface(),
          ipv4_port: Settings.defaults().ipv4_port,
          mstp_local_address: Settings.defaults().mstp_local_address,
          mstp_baud_rate: Settings.defaults().mstp_baud_rate
        )
    end)

    start_supervised!(Stack)
    :ok
  end

  test "status tolerates busy Boot without crashing" do
    :sys.suspend(Boot)

    on_exit(fn ->
      if Process.whereis(Boot), do: :sys.resume(Boot)
    end)

    refute Stack.running?()
    assert Stack.last_error() == nil
    assert Stack.status() == %{running?: false, last_error: nil}
  end

  defp first_ipv4_interface do
    case Settings.interface_options("ipv4") do
      [%{value: value} | _] -> value
      _ -> "lo"
    end
  end
end
