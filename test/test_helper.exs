ExUnit.start()

Application.put_env(:bacview, :bacnet_recipient_address, %BACnet.Protocol.RecipientAddress{
  network: 1,
  address: <<127, 0, 0, 1, 186, 192>>
})
