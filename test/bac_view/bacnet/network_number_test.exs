defmodule BacView.BACnet.NetworkNumberTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.NetworkLayerProtocolMessage
  alias BacView.BACnet.NetworkNumber
  alias BacView.Settings

  setup do
    previous = Settings.get().network_number

    # start_bacnet is false in test; start agent under test
    pid =
      case Process.whereis(NetworkNumber) do
        nil ->
          {:ok, pid} = start_supervised(NetworkNumber)
          pid

        existing ->
          existing
      end

    on_exit(fn ->
      _ = Settings.update(network_number: previous)

      if Process.alive?(pid) and Process.whereis(NetworkNumber) == pid do
        NetworkNumber.reload_from_settings()
      end
    end)

    {:ok, pid: pid}
  end

  test "learns network number when configured is 0" do
    assert {:ok, _} = Settings.update(network_number: 0)
    NetworkNumber.reload_from_settings()
    assert NetworkNumber.configured() == 0
    assert NetworkNumber.learned() == nil
    assert NetworkNumber.quality() == :unknown

    send(
      NetworkNumber,
      {:bacnet_transport, :bacnet_ipv4, {{192, 168, 1, 1}, 47_808},
       {:network, :original_broadcast, nil,
        %NetworkLayerProtocolMessage{
          network_message_type: :network_number_is,
          msg_type: nil,
          data: {100, :configured}
        }}, self()}
    )

    # allow handle_info
    :timer.sleep(20)

    assert NetworkNumber.learned() == 100
    assert NetworkNumber.effective() == 100
    assert NetworkNumber.quality() == :learned
  end

  test "configured number is used as effective" do
    assert {:ok, _} = Settings.update(network_number: 42)
    NetworkNumber.reload_from_settings()

    assert NetworkNumber.configured() == 42
    assert NetworkNumber.effective() == 42
    assert NetworkNumber.quality() == :configured
    assert NetworkNumber.learned() == nil
  end

  test "Network-Number-Is cancels pending configured reply" do
    assert {:ok, _} = Settings.update(network_number: 10)
    NetworkNumber.reload_from_settings()

    send(
      NetworkNumber,
      {:bacnet_transport, :bacnet_ipv4, {{192, 168, 1, 2}, 47_808},
       {:network, :original_broadcast, nil,
        %NetworkLayerProtocolMessage{
          network_message_type: :what_is_network_number,
          msg_type: nil,
          data: nil
        }}, self()}
    )

    :timer.sleep(10)

    send(
      NetworkNumber,
      {:bacnet_transport, :bacnet_ipv4, {{192, 168, 1, 3}, 47_808},
       {:network, :original_broadcast, nil,
        %NetworkLayerProtocolMessage{
          network_message_type: :network_number_is,
          msg_type: nil,
          data: {10, :configured}
        }}, self()}
    )

    :timer.sleep(10)
    # process should still be alive; no crash from cancelled timer
    assert Process.whereis(NetworkNumber)
    assert NetworkNumber.configured() == 10
  end
end
