defmodule BacView.BACnet.Stack.BootTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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

    stack_pid = start_supervised!(Stack)
    %{stack_pid: stack_pid}
  end

  test "start_runtime survives transport startup failure", %{stack_pid: stack_pid} do
    assert {:ok, _} =
             Settings.update(
               transport: "mstp",
               interface: "ttyS0",
               mstp_local_address: 127,
               mstp_baud_rate: :auto
             )

    parent = self()

    _log =
      capture_log(fn ->
        send(parent, {:result, Boot.start_runtime()})
      end)

    assert_receive {:result, {:error, _result}}
    assert Process.alive?(stack_pid)
    assert is_pid(Process.whereis(Boot))
    refute Stack.running?()
    assert Boot.last_error() != nil
  end

  test "restart retries after a failed start" do
    assert {:ok, _} =
             Settings.update(
               transport: "mstp",
               interface: "ttyS0",
               mstp_local_address: 127,
               mstp_baud_rate: :auto
             )

    parent = self()

    _log =
      capture_log(fn ->
        send(parent, {:first, Boot.start_runtime()})
        send(parent, {:second, Boot.restart()})
      end)

    assert_receive {:first, {:error, _first}}
    assert_receive {:second, {:error, _second}}
    refute Stack.running?()
  end

  @tag :ipv4_runtime
  test "resubscribes dependents when runtime children restart" do
    assert {:ok, settings} = Settings.update(transport: "ipv4", ipv4_port: 48_123)
    assert settings.interface

    assert :ok = Boot.start_runtime()

    client = BacView.BACnet.ClientStack
    original_pid = Process.whereis(client)
    assert is_pid(original_pid)

    Process.exit(original_pid, :kill)
    wait_for_new_client_pid(client, original_pid)

    send(Boot, :check_runtime)

    assert Process.whereis(client) != original_pid

    state = :sys.get_state(Boot)

    assert state.runtime_snapshot.client == Process.whereis(client)
  end

  defp first_ipv4_interface do
    case Settings.interface_options("ipv4") do
      [%{value: value} | _] -> value
      _ -> "lo"
    end
  end

  defp wait_for_new_client_pid(client, original_pid, attempts \\ 50)

  defp wait_for_new_client_pid(_client, _original_pid, 0),
    do: flunk("client process did not restart")

  defp wait_for_new_client_pid(client, original_pid, attempts) do
    case Process.whereis(client) do
      pid when is_pid(pid) and pid != original_pid ->
        pid

      _ ->
        Process.sleep(20)
        wait_for_new_client_pid(client, original_pid, attempts - 1)
    end
  end
end
