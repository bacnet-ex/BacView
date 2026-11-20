defmodule BacView.BACnet.SCRuntimeTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.NpciTarget
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PropertyValue
  alias BACnet.Protocol.Services.Ack.ReadPropertyAck
  alias BACnet.Protocol.Services.ConfirmedCovNotification
  alias BACnet.Protocol.Services.IAm
  alias BACnet.Protocol.Services.ReadProperty
  alias BACnet.Protocol.Services.SubscribeCovProperty
  alias BACnet.Protocol.Services.WhoIs
  alias BACnet.Protocol.Services.WriteProperty
  alias BACnet.Stack.Transport.ScTransport.Credentials
  alias BACnet.Stack.Transport.ScTransport.Hub
  alias BACnet.Stack.Transport.ScTransport.Node, as: SCNode
  alias BacView.BACnet.Address
  alias BacView.BACnet.Cache
  alias BacView.BACnet.Client
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.ForeignRegistration
  alias BacView.BACnet.SCCredentials
  alias BacView.BACnet.SinglePropertyRead
  alias BacView.BACnet.Stack
  alias BacView.BACnet.Stack.Boot
  alias BacView.BACnet.SubscriptionManager
  alias BacView.Settings
  alias BacView.Test.BacnetEtsLock
  alias BacView.Test.SCTestCertificates

  @moduletag :tmp_dir
  @peer_vmac <<2, 0, 0, 0, 0, 42>>
  @device %ObjectIdentifier{type: :device, instance: 48_001}
  @object %ObjectIdentifier{type: :analog_value, instance: 3}
  @route %NpciTarget{net: 77, address: <<0, 42>>}

  setup %{tmp_dir: tmp_dir} do
    previous_directory = Application.fetch_env(:bacview, :sc_credentials_directory)
    previous_cov_client = Application.fetch_env(:bacview, :cov_client)
    previous_settings = Settings.get()
    Application.put_env(:bacview, :sc_credentials_directory, tmp_dir)
    Application.put_env(:bacview, :cov_client, Client)

    on_exit(fn ->
      case previous_directory do
        {:ok, directory} -> Application.put_env(:bacview, :sc_credentials_directory, directory)
        :error -> Application.delete_env(:bacview, :sc_credentials_directory)
      end

      case previous_cov_client do
        {:ok, module} -> Application.put_env(:bacview, :cov_client, module)
        :error -> Application.delete_env(:bacview, :cov_client)
      end

      BacnetEtsLock.delete_tables!(Cache.tables())
      Discovery.set_acceptance_filters(low_limit: nil, high_limit: nil, vendor_id: nil)

      Settings.update(
        transport: previous_settings.transport,
        sc_primary_hub_uri: previous_settings.sc_primary_hub_uri,
        sc_failover_hub_uri: previous_settings.sc_failover_hub_uri,
        bbmd_host: previous_settings.bbmd_host
      )
    end)

    :ok = BacnetEtsLock.reset_tables!(Cache.tables())
    start_supervised!(Stack)
    start_supervised!(ForeignRegistration)
    start_supervised!(Discovery)
    start_supervised!(SubscriptionManager)

    ca = SCTestCertificates.issuer()
    {cert, key, issuers} = SCTestCertificates.pem(ca, "Explorer")
    assert {:ok, summary} = SCCredentials.import_pem(cert, key, issuers)
    %{ca: ca, credential_id: summary.id, private_key: key}
  end

  @tag timeout: 90_000, capture_log: true
  test "discovers and exchanges BACnet services over SC and survives hub failover", context do
    primary_options = hub_options(context.ca, 1)
    primary = start_hub(:primary, primary_options)
    primary_port = Hub.port(primary)
    failover = start_hub(:failover, hub_options(context.ca, 2))

    primary_uri = hub_uri(primary_port)
    failover_uri = hub_uri(Hub.port(failover))

    assert {:ok, _settings} =
             Settings.update(
               transport: "bacnet_sc",
               sc_primary_hub_uri: primary_uri,
               sc_failover_hub_uri: failover_uri,
               bbmd_host: "192.0.2.1"
             )

    assert ForeignRegistration.scan_route() == :local
    assert {:error, :bbmd_ipv4_only} = ForeignRegistration.register("192.0.2.1")

    assert :ok = Boot.start_runtime()
    await_hub(:primary)
    assert Stack.status().sc_credential_id == context.credential_id

    assert {:ok, children} = BacView.BACnet.Stack.Runtime.build_children()
    refute inspect(children) =~ "PRIVATE KEY"

    refute File.read!(Application.fetch_env!(:bacview, :runtime_settings_path)) =~
             context.private_key

    client = Process.whereis(Stack.client())
    node = Process.whereis(Stack.transport())

    peer =
      start_supervised!(
        {SCNode,
         [
           self(),
           [
             primary_hub_uri: primary_uri,
             failover_hub_uri: failover_uri,
             device_uuid: <<3::128>>,
             vmac: @peer_vmac,
             credentials: credentials(context.ca, "Responder"),
             min_reconnect_time: 2,
             max_reconnect_time: 4
           ]
         ]}
      )

    await(fn -> SCNode.status(peer).active == :primary end)

    explorer = SCNode.get_local_address(node)
    read_direct_property(peer, explorer, @route)
    discover_device(peer, explorer)
    read_direct_property(peer, explorer, nil)
    read_routed_property(peer, explorer)
    write_routed_property(peer, explorer)
    subscribe_cov(peer, explorer)
    send_confirmed_cov(peer, explorer)

    :ok = stop_supervised(:primary)
    await_hub(:failover)
    await(fn -> SCNode.status(peer).active == :failover end)
    assert Process.whereis(Stack.client()) == client
    assert Process.whereis(Stack.transport()) == node

    assert {:ok, %SubscribeCovProperty{process_identifier: 3}} =
             acknowledge_subscription(peer, explorer)

    read_direct_property(peer, explorer, nil)

    start_hub(:primary, Keyword.put(primary_options, :port, primary_port))
    await_hub(:primary, 35_000)
    await(fn -> SCNode.status(peer).active == :primary end)

    assert {:ok, %SubscribeCovProperty{process_identifier: 3}} =
             acknowledge_subscription(peer, explorer)

    assert Process.whereis(Stack.client()) == client
    assert SCNode.get_local_address(node) == explorer
  end

  @tag capture_log: true
  test "credential files are required and invalid files keep the SC stack offline", %{
    tmp_dir: directory
  } do
    assert {:ok, _settings} =
             Settings.update(transport: "bacnet_sc", sc_primary_hub_uri: "wss://localhost/")

    File.rm!(Path.join(directory, "credentials.json"))
    assert {:error, missing_error} = Boot.start_runtime()
    assert inspect(missing_error) =~ ":missing_sc_credentials"
    refute Stack.running?()

    File.write!(Path.join(directory, "credentials.json"), "invalid file")
    assert {:error, invalid_error} = Boot.restart()
    assert inspect(invalid_error) =~ ":invalid_sc_credentials"
    refute Stack.running?()
  end

  @tag capture_log: true
  test "rejects a hub signed by an untrusted issuer and reports readiness separately" do
    hub = start_hub(:untrusted, hub_options(SCTestCertificates.issuer(), 1))

    assert {:ok, _settings} =
             Settings.update(
               transport: "bacnet_sc",
               sc_primary_hub_uri: hub_uri(Hub.port(hub)),
               sc_failover_hub_uri: nil
             )

    assert :ok = Boot.start_runtime()
    await_hub(:retrying)

    assert %{running?: true, ready?: false, last_error: reason} = Stack.status()
    assert reason in [:sc_tls_failed, :sc_connection_failed]
    assert {:error, :not_connected} = Client.read_property(@peer_vmac, @object, :present_value)
  end

  defp discover_device(peer, explorer) do
    {:ok, iam} =
      IAm.to_apdu(
        %IAm{
          device: @device,
          max_apdu: 1476,
          segmentation_supported: :no_segmentation,
          vendor_id: 1
        },
        []
      )

    assert :ok = Discovery.scan_async(self(), timeout: 600)

    assert {^explorer, %{destination: destination}, %APDU.UnconfirmedServiceRequest{} = who_is} =
             receive_apdu(peer, :who_is)

    assert destination == %NpciTarget{net: 65_535, address: nil}
    assert {:ok, %WhoIs{}} = APDU.UnconfirmedServiceRequest.to_service(who_is)
    assert :ok = SCNode.send(peer, explorer, iam)
    assert_receive {:scan_complete, {:ok, [%{address: @peer_vmac} = device]}}, 3_000
    assert Map.get(device, :npci_source) == nil

    assert {:ok, opts} =
             Discovery.parse_scan_params(%{
               "target_ip" => Address.format_destination(@peer_vmac),
               "timeout_ms" => "600"
             })

    assert :ok = Discovery.scan_async(self(), opts)
    assert {^explorer, %{destination: nil}, _request} = receive_apdu(peer, :who_is)
    assert :ok = SCNode.send(peer, explorer, iam, source: @route)

    assert_receive {:scan_complete, {:ok, [%{address: @peer_vmac, npci_source: @route}]}}, 3_000

    assert {:ok, opts} =
             Discovery.parse_scan_params(%{
               "target_ip" => Address.format_destination(@peer_vmac),
               "npci_source" => "77/00:2A",
               "timeout_ms" => "600"
             })

    assert :ok = Discovery.scan_async(self(), opts)
    route = @route

    assert {^explorer, %{destination: ^route, source: nil}, _request} =
             receive_apdu(peer, :who_is)

    assert :ok = SCNode.send(peer, explorer, iam, source: route)

    assert_receive {:scan_complete, {:ok, [%{address: @peer_vmac, npci_source: ^route}]}}, 3_000
  end

  defp read_direct_property(peer, explorer, route) do
    task =
      Task.async(fn ->
        SinglePropertyRead.from_form(%{
          "locator" => "address",
          "address" => Address.format_destination(@peer_vmac),
          "npci_source" => if(route, do: Address.format_npci_target(route), else: ""),
          "object_type" => "analog-value",
          "instance" => "3",
          "property" => "present-value"
        })
      end)

    reply_to_read(peer, explorer, route)
    assert {:ok, %{value: 21.5, destination: @peer_vmac}} = Task.await(task)
  end

  defp read_routed_property(peer, explorer) do
    task =
      Task.async(fn ->
        Client.read_property(@peer_vmac, @object, :present_value, device_id: @device.instance)
      end)

    reply_to_read(peer, explorer, @route)
    assert {:ok, 21.5} = Task.await(task)
  end

  defp reply_to_read(peer, explorer, route) do
    assert {^explorer, %{destination: ^route}, request} = receive_apdu(peer, :read_property)

    assert {:ok, %ReadProperty{object_identifier: @object, property_identifier: :present_value}} =
             ReadProperty.from_apdu(request)

    ack = %ReadPropertyAck{
      object_identifier: @object,
      property_identifier: :present_value,
      property_array_index: nil,
      property_value: Encoding.create!({:real, 21.5})
    }

    assert {:ok, encoded} = ReadPropertyAck.to_apdu(ack, request.invoke_id)
    assert :ok = SCNode.send(peer, explorer, encoded, source: route)
  end

  defp write_routed_property(peer, explorer) do
    value = Encoding.create!({:real, 23.0})

    task =
      Task.async(fn ->
        Client.write_property(@peer_vmac, @object, :present_value, value,
          device_id: @device.instance
        )
      end)

    assert {^explorer, %{destination: @route}, request} = receive_apdu(peer, :write_property)

    assert {:ok, %WriteProperty{property_value: %Encoding{value: 23.0}}} =
             WriteProperty.from_apdu(request)

    ack = %APDU.SimpleACK{invoke_id: request.invoke_id, service: :write_property}
    assert :ok = SCNode.send(peer, explorer, ack, source: @route)
    assert :ok = Task.await(task)
  end

  defp subscribe_cov(peer, explorer) do
    task =
      Task.async(fn ->
        SubscriptionManager.subscribe(@device.instance, @object, :present_value,
          process_id: 3,
          confirmed: true
        )
      end)

    assert {:ok, %SubscribeCovProperty{process_identifier: 3}} =
             acknowledge_subscription(peer, explorer)

    assert :ok = Task.await(task)
  end

  defp acknowledge_subscription(peer, explorer) do
    assert {^explorer, %{destination: @route}, request} =
             receive_apdu(peer, :subscribe_cov_property)

    ack = %APDU.SimpleACK{invoke_id: request.invoke_id, service: :subscribe_cov_property}
    assert :ok = SCNode.send(peer, explorer, ack, source: @route)
    SubscribeCovProperty.from_apdu(request)
  end

  defp send_confirmed_cov(peer, explorer) do
    notification = %ConfirmedCovNotification{
      process_identifier: 3,
      initiating_device: @device,
      monitored_object: @object,
      time_remaining: 120,
      property_values: [
        %PropertyValue{
          property_identifier: :present_value,
          property_array_index: nil,
          property_value: Encoding.create!({:real, 24.0}),
          priority: nil
        }
      ]
    }

    assert {:ok, apdu} = ConfirmedCovNotification.to_apdu(notification, invoke_id: 31)
    assert :ok = SCNode.send(peer, explorer, apdu, source: @route)

    assert {^explorer, %{destination: @route}, %APDU.SimpleACK{invoke_id: 31}} =
             receive_apdu(peer, :confirmed_cov_notification)

    await(fn ->
      Enum.any?(SubscriptionManager.list_notifications(@device.instance), &(&1.value == 24.0))
    end)
  end

  defp receive_apdu(peer, service) do
    receive do
      {:bacnet_transport, {:bacnet_sc, SCNode}, source, {:apdu, _bvlc, npci, raw}, ^peer} ->
        case APDU.decode(raw) do
          {:ok, %{service: ^service} = apdu} ->
            if relevant?(apdu), do: {source, npci, apdu}, else: receive_apdu(peer, service)

          _request ->
            receive_apdu(peer, service)
        end
    after
      7_000 -> flunk("No BACnet/SC #{service} message received")
    end
  end

  # A discovered device can trigger additional reads for its name and description.
  defp relevant?(%APDU.ConfirmedServiceRequest{service: :read_property} = request) do
    match?({:ok, %ReadProperty{object_identifier: @object}}, ReadProperty.from_apdu(request))
  end

  defp relevant?(_request), do: true

  defp start_hub(id, opts) do
    start_supervised!(%{id: id, start: {Hub, :start_link, [opts]}, restart: :temporary})
  end

  defp hub_options(ca, number) do
    [
      ip: {127, 0, 0, 1},
      port: 0,
      device_uuid: <<number::128>>,
      vmac: <<2, 0, 0, 0, 0, number>>,
      credentials: credentials(ca, "Hub #{number}")
    ]
  end

  defp credentials(ca, name) do
    {cert, key, issuers} = SCTestCertificates.pem(ca, name)
    {:ok, credentials} = Credentials.from_pem(cert, key, issuers)
    credentials
  end

  defp hub_uri(port), do: "wss://127.0.0.1:#{port}/"

  defp await_hub(role, timeout \\ 25_000) do
    await(fn -> Stack.status().sc_link == role end, timeout)
  end

  defp await(fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    if fun.() do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "BACnet/SC condition timed out"
      Process.sleep(50)
      poll(fun, deadline)
    end
  end
end
