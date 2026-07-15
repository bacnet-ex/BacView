defmodule BacView.BACnet.IAmCollectorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.BvlcForwardedNPDU
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.IAm
  alias BacView.BACnet.IAmCollector

  @iam_apdu %UnconfirmedServiceRequest{
    service: :i_am,
    parameters: [
      object_identifier: %ObjectIdentifier{type: :device, instance: 42},
      unsigned_integer: 1476,
      enumerated: 3,
      unsigned_integer: 999
    ]
  }

  test "parse_iam decodes a standard I-Am APDU" do
    assert {:ok, %IAm{device: %{instance: 42}}} = IAmCollector.parse_iam(@iam_apdu)
  end

  test "device_address prefers originating address from forwarded NPDU" do
    bvlc = %BvlcForwardedNPDU{
      originating_ip: {10, 0, 0, 5},
      originating_port: 47_808
    }

    assert IAmCollector.device_address({{192, 168, 1, 79}, 47_808}, bvlc) ==
             {{10, 0, 0, 5}, 47_808}
  end

  test "device_address falls back to transport source" do
    assert IAmCollector.device_address({{192, 168, 1, 79}, 47_808}, :original_unicast) ==
             {{192, 168, 1, 79}, 47_808}
  end

  test "npci_source_from extracts NPCI source target" do
    npci = %BACnet.Protocol.NPCI{
      priority: :normal,
      expects_reply: false,
      destination: nil,
      source: %BACnet.Protocol.NpciTarget{net: 2, address: 42},
      hopcount: nil,
      is_network_message: false
    }

    assert IAmCollector.npci_source_from(npci) == %BACnet.Protocol.NpciTarget{net: 2, address: 42}
    assert IAmCollector.npci_source_from(nil) == nil
  end

  test "collect logs npci source in device info message" do
    npci = %BACnet.Protocol.NPCI{
      priority: :normal,
      expects_reply: false,
      destination: nil,
      source: %BACnet.Protocol.NpciTarget{net: 3, address: 200},
      hopcount: nil,
      is_network_message: false
    }

    previous_level = Logger.level()
    on_exit(fn -> Logger.configure(level: previous_level) end)

    log =
      capture_log(fn ->
        Logger.configure(level: :info)

        source = {{10, 130, 0, 221}, 47_808}
        addr_info = {source, :original_unicast, npci}
        send(self(), {:bacnet_client, make_ref(), @iam_apdu, addr_info, self()})
        IAmCollector.collect(200)
      end)

    assert log =~
             "IAmCollector: device 42 at 10.130.0.221:47808 (source 10.130.0.221:47808, npci source 3/200)"
  end

  test "collect gathers I-Am notifications from the mailbox" do
    task =
      Task.async(fn ->
        source = {{192, 168, 1, 79}, 47_808}

        npci = %BACnet.Protocol.NPCI{
          priority: :normal,
          expects_reply: false,
          destination: nil,
          source: nil,
          hopcount: nil,
          is_network_message: false
        }

        addr_info = {source, :original_unicast, npci}
        send(self(), {:bacnet_client, make_ref(), @iam_apdu, addr_info, self()})

        [{address, iam, _npci_source, source_address}] = IAmCollector.collect(200)
        {address, iam.device.instance, source_address}
      end)

    assert Task.await(task) == {{{192, 168, 1, 79}, 47_808}, 42, {{192, 168, 1, 79}, 47_808}}
  end
end
