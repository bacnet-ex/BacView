defmodule BacView.BACnet.DiscoverySnifferTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.NPCI
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services.IAm
  alias BacView.BACnet.DiscoverySniffer

  @cov_apdu %UnconfirmedServiceRequest{
    service: :unconfirmed_cov_notification,
    parameters: []
  }

  @bacnet_msg {
    :bacnet_client,
    nil,
    @cov_apdu,
    {{{192, 168, 1, 79}, 47_808}, :original_unicast,
     %NPCI{
       priority: :normal,
       expects_reply: false,
       destination: nil,
       source: nil,
       hopcount: nil,
       is_network_message: false
     }},
    self()
  }

  test "ignores BACnet traffic while not collecting" do
    capture_log(fn ->
      {:ok, pid} = GenServer.start(DiscoverySniffer, [], [])

      send(pid, @bacnet_msg)

      assert Process.alive?(pid)
      assert :sys.get_state(pid).active == nil
    end)
  end

  @iam_apdu %UnconfirmedServiceRequest{
    service: :i_am,
    parameters: [
      object_identifier: %ObjectIdentifier{type: :device, instance: 42},
      unsigned_integer: 1476,
      enumerated: 3,
      unsigned_integer: 999
    ]
  }

  test "collection timer starts only after start_collect" do
    capture_log(fn ->
      {:ok, pid} = GenServer.start(DiscoverySniffer, [], [])

      ref = GenServer.call(pid, {:arm, nil})

      # Simulate a slow Who-Is send; with the old arm-time timer this would expire here.
      Process.sleep(250)

      npci = %NPCI{
        priority: :normal,
        expects_reply: false,
        destination: nil,
        source: nil,
        hopcount: nil,
        is_network_message: false
      }

      source = {{192, 168, 1, 79}, 47_808}
      addr_info = {source, :original_unicast, npci}
      send(pid, {:bacnet_client, nil, @iam_apdu, addr_info, self()})

      :ok = GenServer.call(pid, {:start_collect, ref, 500})

      await_task = Task.async(fn -> GenServer.call(pid, {:await, ref}, 1_000) end)

      assert {:ok, responses} = Task.await(await_task, 1_000)
      assert [{address, %IAm{device: %{instance: 42}}}] = responses
      assert address == {{192, 168, 1, 79}, 47_808}
    end)
  end
end
