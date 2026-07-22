ExUnit.start()

# MAC only is used at runtime; network-number is chosen per device (0 = local BACnet net).
Application.put_env(:bacview, :bacnet_recipient_address, %BACnet.Protocol.RecipientAddress{
  network: 0,
  address: <<127, 0, 0, 1, 186, 192>>
})

# Remove this process's temp runtime settings file after the suite (see config/test.exs).
ExUnit.after_suite(fn _results ->
  path = Application.get_env(:bacview, :runtime_settings_path)

  if is_binary(path) do
    File.rm(path)
  end
end)
