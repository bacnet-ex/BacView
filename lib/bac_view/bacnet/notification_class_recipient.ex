defmodule BacView.BACnet.NotificationClassRecipient do
  @moduledoc """
  Enrolls BacView in Notification Class `recipient_list` properties so the local
  device receives event notifications. Unenrolling removes BacView from each list.
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.DaysOfWeek
  alias BACnet.Protocol.Destination
  alias BACnet.Protocol.EventTransitionBits
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Stack.Transport.IPv4Transport
  alias BacView.BACnet.Client
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.Stack

  @table :bacview_nc_recipients
  @notification_process_id 0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec subscribe_all(integer(), pid(), keyword()) :: :ok
  def subscribe_all(device_id, progress_pid, opts \\ []) do
    GenServer.cast(__MODULE__, {:subscribe_all, device_id, progress_pid, opts})
  end

  @spec unsubscribe_all(integer(), pid(), keyword()) :: :ok
  def unsubscribe_all(device_id, progress_pid, opts \\ []) do
    GenServer.cast(__MODULE__, {:unsubscribe_all, device_id, progress_pid, opts})
  end

  @spec enrolled_count(integer()) :: non_neg_integer()
  def enrolled_count(device_id) do
    length(list_enrolled(device_id))
  end

  @spec list_enrolled(integer()) :: [map()]
  def list_enrolled(device_id) do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.filter(fn {{dev_id, _instance}, _entry} -> dev_id == device_id end)
      |> Enum.map(fn {_key, entry} -> entry end)
      |> Enum.sort_by(& &1.instance, :asc)
    end
  end

  @spec sync_enrollment_state(integer(), [map()]) :: %{
          enrolled: non_neg_integer(),
          total: non_neg_integer()
        }
  def sync_enrollment_state(device_id, objects) do
    objects = notification_class_objects(device_id, objects: objects)

    Enum.each(objects, &sync_object_enrollment(device_id, &1))

    %{enrolled: enrolled_count(device_id), total: length(objects)}
  end

  @doc false
  @spec add_self_to_recipient_list([Destination.t()]) :: [Destination.t()]
  def add_self_to_recipient_list(destinations) when is_list(destinations) do
    if recipient_list_contains_self?(destinations) do
      destinations
    else
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      destinations ++ [default_destination()]
    end
  end

  @doc false
  @spec remove_self_from_recipient_list([Destination.t()]) :: [Destination.t()]
  def remove_self_from_recipient_list(destinations) when is_list(destinations) do
    Enum.reject(destinations, fn entry ->
      case decode_destination(entry) do
        %Destination{} = destination -> destination_for_self?(destination)
        _destinations -> false
      end
    end)
  end

  @doc false
  @spec recipient_list_contains_self?([Destination.t()]) :: boolean()
  def recipient_list_contains_self?(destinations) when is_list(destinations) do
    destinations
    |> Enum.map(&decode_destination/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&destination_for_self?/1)
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:subscribe_all, device_id, progress_pid, opts}, state) do
    run_bulk(device_id, progress_pid, :subscribe, opts)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:unsubscribe_all, device_id, progress_pid, opts}, state) do
    run_bulk(device_id, progress_pid, :unsubscribe, opts)
    {:noreply, state}
  end

  defp run_bulk(device_id, progress_pid, action, opts) do
    objects = notification_class_objects(device_id, opts)
    total = length(objects)

    Task.start(fn ->
      {succeeded, failed} =
        Enum.reduce(Enum.with_index(objects, 1), {0, 0}, fn {obj, idx}, {ok_count, err_count} ->
          object_id = %ObjectIdentifier{type: :notification_class, instance: obj.instance}

          result =
            case action do
              :subscribe -> enroll(device_id, object_id)
              :unsubscribe -> unenroll(device_id, object_id)
            end

          send(progress_pid, {:nc_bulk_progress, idx, total})

          case result do
            :ok -> {ok_count + 1, err_count}
            _device_id -> {ok_count, err_count + 1}
          end
        end)

      sync = sync_enrollment_state(device_id, objects)

      send(progress_pid, {
        :nc_bulk_done,
        Map.merge(sync, %{succeeded: succeeded, failed: failed, action: action})
      })
    end)
  end

  defp enroll(device_id, object_id) do
    with {:ok, device} <- fetch_device(device_id) do
      destination = default_destination()

      case Client.add_list_element(device.address, object_id, :recipient_list, destination,
             device_id: device_id
           ) do
        :ok ->
          mark_enrolled(device_id, object_id)
          :ok

        {:error, reason} ->
          Logger.debug(
            "AddListElement failed for #{object_id.type}:#{object_id.instance}: #{inspect(reason)}"
          )

          enroll_via_write_property(device, device_id, object_id)
      end
    end
  end

  defp enroll_via_write_property(device, device_id, object_id) do
    with {:ok, current} <- read_recipient_list(device.address, object_id, device_id) do
      if recipient_list_contains_self?(current) do
        mark_enrolled(device_id, object_id)
        :ok
      else
        updated = add_self_to_recipient_list(current)

        case write_recipient_list(device.address, object_id, updated, device_id) do
          :ok ->
            mark_enrolled(device_id, object_id)
            :ok

          {:error, _device} = err ->
            err
        end
      end
    end
  end

  defp unenroll(device_id, object_id) do
    with {:ok, device} <- fetch_device(device_id) do
      destination = default_destination()

      case Client.remove_list_element(device.address, object_id, :recipient_list, destination,
             device_id: device_id
           ) do
        :ok ->
          mark_unenrolled(device_id, object_id)
          :ok

        {:error, reason} ->
          Logger.debug(
            "RemoveListElement failed for #{object_id.type}:#{object_id.instance}: #{inspect(reason)}"
          )

          unenroll_via_write_property(device, device_id, object_id)
      end
    end
  end

  defp unenroll_via_write_property(device, device_id, object_id) do
    with {:ok, current} <- read_recipient_list(device.address, object_id, device_id) do
      if recipient_list_contains_self?(current) do
        updated = remove_self_from_recipient_list(current)

        case write_recipient_list(device.address, object_id, updated, device_id) do
          :ok ->
            mark_unenrolled(device_id, object_id)
            :ok

          {:error, _device} = err ->
            err
        end
      else
        mark_unenrolled(device_id, object_id)
        :ok
      end
    end
  end

  defp sync_object_enrollment(device_id, %{instance: instance}) do
    object_id = %ObjectIdentifier{type: :notification_class, instance: instance}

    with {:ok, device} <- fetch_device(device_id),
         {:ok, current} <- read_recipient_list(device.address, object_id, device_id) do
      if recipient_list_contains_self?(current) do
        mark_enrolled(device_id, object_id)
      else
        mark_unenrolled(device_id, object_id)
      end
    else
      _device_id -> :ok
    end
  end

  defp notification_class_objects(device_id, opts) do
    case Keyword.get(opts, :objects) do
      objects when is_list(objects) ->
        Enum.filter(objects, &(&1.type == :notification_class))

      _device_id ->
        Enum.filter(DeviceSession.objects(device_id), &(&1.type == :notification_class))
    end
  end

  defp read_recipient_list(destination, object_id, device_id) do
    case Client.read_property(destination, object_id, :recipient_list, device_id: device_id) do
      {:ok, value} -> {:ok, normalize_recipient_list(value)}
      {:error, _destination} = err -> err
    end
  end

  defp write_recipient_list(destination, object_id, destinations, device_id) do
    Client.write_property(
      destination,
      object_id,
      :recipient_list,
      BACnetArray.from_list(destinations),
      device_id: device_id
    )
  end

  defp normalize_recipient_list(%BACnetArray{} = array), do: BACnetArray.to_list(array)

  defp normalize_recipient_list(destinations) when is_list(destinations), do: destinations
  defp normalize_recipient_list(_normalize_recipient_list), do: []

  defp decode_destination(%Destination{} = destination), do: destination

  defp decode_destination(%Encoding{} = encoding) do
    with {:ok, raw} <- Encoding.to_encoding(encoding),
         {:ok, {destination, _rest}} <- Destination.parse(List.wrap(raw)) do
      destination
    else
      _destination -> decode_destination_from_encoding_value(encoding)
    end
  end

  defp decode_destination(other) when is_list(other) do
    case Destination.parse(other) do
      {:ok, {destination, _rest}} -> destination
      _destination -> nil
    end
  end

  defp decode_destination(_destination), do: nil

  defp decode_destination_from_encoding_value(%Encoding{value: value}) when is_list(value) do
    case Destination.parse(value) do
      {:ok, {destination, _rest}} -> destination
      _value -> nil
    end
  end

  defp decode_destination_from_encoding_value(_value), do: nil

  defp default_destination() do
    %Destination{
      recipient: %Recipient{
        type: :address,
        address: local_recipient_address(),
        device: nil
      },
      process_identifier: @notification_process_id,
      issue_confirmed_notifications: notification_confirmed?(),
      transitions: %EventTransitionBits{
        to_offnormal: true,
        to_fault: true,
        to_normal: true
      },
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

  defp destination_for_self?(%Destination{recipient: recipient}),
    do: recipient_for_self?(recipient)

  defp destination_for_self?(_destination_for_self), do: false

  defp recipient_for_self?(%Recipient{
         type: :address,
         address: %RecipientAddress{} = address
       }) do
    address == local_recipient_address()
  end

  defp recipient_for_self?(%Recipient{
         type: :device,
         device: %ObjectIdentifier{type: :device, instance: instance}
       }) do
    instance == local_device_id()
  end

  defp recipient_for_self?(_recipient_for_self), do: false

  defp local_recipient_address() do
    case Application.get_env(:bacview, :bacnet_recipient_address) do
      %RecipientAddress{} = address ->
        address

      _local_recipient_address ->
        {ip, port} = IPv4Transport.get_local_address(Stack.transport())
        %RecipientAddress{network: local_network_number(), address: ip_port_to_mac(ip, port)}
    end
  end

  defp ip_port_to_mac({a, b, c, d}, port) when is_integer(port) do
    <<a, b, c, d, Bitwise.bsr(port, 8), Bitwise.band(port, 0xFF)>>
  end

  defp local_device_id() do
    BacView.Settings.device_id()
  end

  defp local_network_number() do
    BacView.Settings.network_number()
  end

  defp notification_confirmed?() do
    BacView.Settings.cov_confirmed?()
  end

  defp mark_enrolled(device_id, object_id) do
    key = {device_id, object_id.instance}

    :ets.insert(@table, {
      key,
      %{
        device_id: device_id,
        instance: object_id.instance,
        enrolled_at: DateTime.utc_now()
      }
    })
  end

  defp mark_unenrolled(device_id, object_id) do
    :ets.delete(@table, {device_id, object_id.instance})
  end

  defp fetch_device(device_id) do
    case Discovery.get_device(device_id) do
      {:ok, device} -> {:ok, device}
      :error -> {:error, :device_not_found}
    end
  end
end
