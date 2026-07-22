defmodule BacView.BACnet.NotificationClassRecipientTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.DaysOfWeek
  alias BACnet.Protocol.Destination
  alias BACnet.Protocol.EventTransitionBits
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Protocol.Services.AddListElement
  alias BacView.BACnet.{Client, NotificationClassRecipient}

  @local_address %RecipientAddress{network: 1, address: <<127, 0, 0, 1, 186, 192>>}

  defp other_destination do
    %Destination{
      recipient: %Recipient{
        type: :device,
        device: %ObjectIdentifier{type: :device, instance: 42},
        address: nil
      },
      process_identifier: 9,
      issue_confirmed_notifications: false,
      transitions: %EventTransitionBits{to_offnormal: true, to_fault: true, to_normal: true},
      valid_days: %DaysOfWeek{
        monday: true,
        tuesday: true,
        wednesday: true,
        thursday: true,
        friday: true,
        saturday: true,
        sunday: true
      },
      from_time: %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0},
      to_time: %BACnetTime{hour: 23, minute: 59, second: 59, hundredth: 99}
    }
  end

  test "add_self_to_recipient_list appends BacView destination once" do
    list = [other_destination()]

    assert length(NotificationClassRecipient.add_self_to_recipient_list(list)) == 2
    assert NotificationClassRecipient.recipient_list_contains_self?(list) == false

    added = NotificationClassRecipient.add_self_to_recipient_list(list)
    assert NotificationClassRecipient.recipient_list_contains_self?(added)

    assert length(NotificationClassRecipient.add_self_to_recipient_list(added)) == 2
  end

  test "remove_self_from_recipient_list removes only BacView destination" do
    base = [other_destination()]
    with_self = NotificationClassRecipient.add_self_to_recipient_list(base)

    removed = NotificationClassRecipient.remove_self_from_recipient_list(with_self)

    assert removed == base
    refute NotificationClassRecipient.recipient_list_contains_self?(removed)
  end

  test "default destination encodes as flat AddListElement fields" do
    destination = hd(NotificationClassRecipient.add_self_to_recipient_list([]))
    object_id = %ObjectIdentifier{type: :notification_class, instance: 1}

    assert {:ok, elements} = Client.encode_list_elements([destination])
    assert length(elements) == 7
    assert Enum.all?(elements, &match?(%Encoding{}, &1))

    assert {:ok, request} =
             AddListElement.to_apdu(
               %AddListElement{
                 object_identifier: object_id,
                 property_identifier: :recipient_list,
                 property_array_index: nil,
                 elements: elements
               },
               []
             )

    assert request.service == :add_list_element
  end

  test "self destination uses local IP address recipient" do
    [self_entry | _] =
      NotificationClassRecipient.add_self_to_recipient_list([])
      |> Enum.filter(fn %Destination{recipient: %Recipient{type: :address, address: address}} ->
        address == @local_address
      end)

    assert %Destination{
             recipient: %Recipient{
               type: :address,
               address: %RecipientAddress{network: 1, address: <<127, 0, 0, 1, 186, 192>>}
             }
           } = self_entry
  end

  test "sync_enrollment_state with use_scanned marks enrolled from scan data" do
    device_id = 9_100_001
    objects = [%{type: :notification_class, instance: 3}]
    with_self = NotificationClassRecipient.add_self_to_recipient_list([other_destination()])

    scanned = [
      {%ObjectIdentifier{type: :notification_class, instance: 3}, %{recipient_list: with_self}}
    ]

    result =
      NotificationClassRecipient.sync_enrollment_state(device_id, objects,
        use_scanned: true,
        scanned: scanned
      )

    assert result == %{enrolled: 1, total: 1}
    assert NotificationClassRecipient.enrolled_count(device_id) == 1
  end

  test "sync_enrollment_state with use_scanned marks unenrolled from scan data" do
    device_id = 9_100_002
    objects = [%{type: :notification_class, instance: 7}]

    scanned = [
      {%ObjectIdentifier{type: :notification_class, instance: 7},
       %{recipient_list: [other_destination()]}}
    ]

    # Seed enrolled state so we can prove scan data clears it.
    NotificationClassRecipient.sync_enrollment_state(device_id, objects,
      use_scanned: true,
      scanned: [
        {%ObjectIdentifier{type: :notification_class, instance: 7},
         %{recipient_list: NotificationClassRecipient.add_self_to_recipient_list([])}}
      ]
    )

    assert NotificationClassRecipient.enrolled_count(device_id) == 1

    result =
      NotificationClassRecipient.sync_enrollment_state(device_id, objects,
        use_scanned: true,
        scanned: scanned
      )

    assert result == %{enrolled: 0, total: 1}
    assert NotificationClassRecipient.enrolled_count(device_id) == 0
  end

  test "sync_enrollment_state without use_scanned ignores provided scanned data" do
    device_id = 9_100_003
    objects = [%{type: :notification_class, instance: 1}]

    # No discovered device → ReadProperty path fails silently; must not use scanned.
    result =
      NotificationClassRecipient.sync_enrollment_state(device_id, objects,
        use_scanned: false,
        scanned: [
          {%ObjectIdentifier{type: :notification_class, instance: 1},
           %{
             recipient_list: NotificationClassRecipient.add_self_to_recipient_list([])
           }}
        ]
      )

    assert result == %{enrolled: 0, total: 1}
    assert NotificationClassRecipient.enrolled_count(device_id) == 0
  end
end
