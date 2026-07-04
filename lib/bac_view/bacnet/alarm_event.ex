defmodule BacView.BACnet.AlarmEvent do
  @moduledoc """
  BACnet alarm and event tracking via GetAlarmSummary polling and
  Confirmed/UnconfirmedEventNotification routing.
  """
  use GenServer

  alias BACnet.Protocol.APDU.ConfirmedServiceRequest
  alias BACnet.Protocol.APDU.SimpleACK
  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.ObjectIdentifier

  alias BACnet.Protocol.Services.ConfirmedEventNotification
  alias BACnet.Protocol.Services.UnconfirmedEventNotification

  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Client
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.EventRecord
  alias BacView.BACnet.NotificationLogLimit
  alias BacView.PubSub

  @table :bacview_events
  @notification_log :bacview_notification_log
  @notification_seq :bacview_notification_seq
  @topic_alarms "alarms:updates"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec refresh(integer()) :: :ok | {:error, term()}
  def refresh(device_id) do
    GenServer.call(__MODULE__, {:refresh, device_id}, 60_000)
  end

  @spec list_events(integer()) :: [map()]
  def list_events(device_id), do: list_polled_events(device_id)

  @spec list_all_active_polled_events() :: [map()]
  def list_all_active_polled_events() do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, event} -> event end)
      |> Enum.filter(&(&1.source == :poll and EventRecord.active?(&1)))
    end
  end

  @spec list_polled_events(integer()) :: [map()]
  def list_polled_events(device_id) do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.filter(fn {{dev_id, _type, _instance}, _event} -> dev_id == device_id end)
      |> Enum.map(fn {_key, event} -> event end)
      |> Enum.filter(&(&1.source == :poll))
      |> Enum.sort_by(
        fn event ->
          {event.object_id.type, event.object_id.instance}
        end,
        :asc
      )
    end
  end

  @spec list_notifications(integer()) :: [map()]
  def list_notifications(device_id) do
    if :ets.whereis(@notification_log) == :undefined do
      []
    else
      @notification_log
      |> :ets.tab2list()
      |> Enum.filter(fn {{dev_id, _device_id, _list_notifications2}, _list_notifications3} ->
        dev_id == device_id
      end)
      |> Enum.sort_by(
        fn {{_device_id, neg_micro, seq}, _list_notifications2} -> {neg_micro, seq} end,
        :asc
      )
      |> Enum.map(fn {_key, entry} -> entry end)
    end
  end

  @spec summary(integer()) :: map()
  def summary(device_id) do
    device_id |> list_polled_events() |> EventRecord.summary()
  end

  @spec global_summary() :: map()
  def global_summary() do
    if :ets.whereis(@table) == :undefined do
      EventRecord.summary([])
    else
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, event} -> event end)
      |> Enum.filter(&(&1.source == :poll))
      |> EventRecord.summary()
    end
  end

  @spec export(integer(), :json | :csv) :: {:ok, String.t()} | {:error, term()}
  def export(device_id, format), do: BacView.BACnet.EventExport.export(device_id, format)

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    if :ets.whereis(@notification_log) == :undefined do
      :ets.new(@notification_log, [:named_table, :ordered_set, :public, read_concurrency: true])
    end

    if :ets.whereis(@notification_seq) == :undefined do
      :ets.new(@notification_seq, [:named_table, :set, :public])
    end

    maybe_subscribe_client()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:refresh, device_id}, _from, state) do
    result =
      with {:ok, device} <- fetch_device(device_id),
           {:ok, summaries} <- fetch_alarm_summaries(device.address) do
        store_polled_events(device_id, summaries)
        broadcast_updates(device_id)
        :ok
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(
        {:bacnet_client, ref, apdu, {source, _bvlc, _npci}, client_pid},
        state
      ) do
    case apdu do
      %UnconfirmedServiceRequest{service: :unconfirmed_event_notification} = req ->
        case UnconfirmedServiceRequest.to_service(req) do
          {:ok, %UnconfirmedEventNotification{} = notif} ->
            handle_event_notification(notif, source, ref, client_pid, false)

          _resubscribe_client ->
            :ok
        end

      %ConfirmedServiceRequest{service: :confirmed_event_notification, invoke_id: invoke_id} = req ->
        case ConfirmedServiceRequest.to_service(req) do
          {:ok, %ConfirmedEventNotification{} = notif} ->
            handle_event_notification(notif, source, ref, client_pid, true, invoke_id)

          _resubscribe_client ->
            :ok
        end

      _resubscribe_client ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:resubscribe_client, state) do
    StackClient.subscribe(Client.stack_client(), self())
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp maybe_subscribe_client() do
    if BacView.BACnet.Stack.running?() do
      StackClient.subscribe(Client.stack_client(), self())
    end
  end

  @doc false
  @spec resubscribe_client() :: :ok
  def resubscribe_client() do
    if Process.whereis(__MODULE__) do
      send(__MODULE__, :resubscribe_client)
    end

    :ok
  end

  defp fetch_alarm_summaries(destination, opts \\ []) do
    case Client.get_alarm_summary(destination, opts) do
      {:ok, %{summaries: summaries}} -> {:ok, summaries}
      {:error, _destination} = err -> err
    end
  end

  defp store_polled_events(device_id, summaries) do
    Enum.each(summaries, fn summary ->
      record = EventRecord.from_alarm_summary(device_id, summary)
      upsert_polled_event(record)
    end)
  end

  defp handle_event_notification(
         notification,
         source,
         ref,
         client_pid,
         confirmed?,
         invoke_id \\ 0
       ) do
    device_id = find_device_id(notification.initiating_device, source)

    if confirmed? and is_reference(ref) do
      ack = %SimpleACK{invoke_id: invoke_id, service: :confirmed_event_notification}
      _handle_event_notification = StackClient.reply(client_pid, ref, ack, [])
    end

    if device_id do
      record = EventRecord.from_notification(device_id, notification)
      log_entry = append_notification(record)
      broadcast_updates(device_id)

      Phoenix.PubSub.broadcast(
        PubSub,
        device_topic(device_id),
        {:alarm_update, log_entry}
      )
    end
  end

  defp upsert_polled_event(%{device_id: device_id, object_id: object_id} = record) do
    key = EventRecord.key(device_id, object_id)

    merged =
      case :ets.lookup(@table, key) do
        [{^key, existing}] -> EventRecord.merge(existing, record)
        [] -> record
      end

    :ets.insert(@table, {key, merged})
  end

  defp append_notification(record) do
    device_id = record.device_id
    seq = next_notification_seq(device_id)
    received_at = DateTime.utc_now()
    micro = DateTime.to_unix(received_at, :microsecond)
    key = {device_id, -micro, seq}

    log_entry =
      record
      |> Map.put(:log_id, seq)
      |> Map.put(:received_at, received_at)

    :ets.insert(@notification_log, {key, log_entry})
    NotificationLogLimit.prune(@notification_log, device_id)
    log_entry
  end

  defp next_notification_seq(device_id) do
    case :ets.lookup(@notification_seq, device_id) do
      [{^device_id, seq}] ->
        next = seq + 1
        :ets.insert(@notification_seq, {device_id, next})
        next

      [] ->
        :ets.insert(@notification_seq, {device_id, 1})
        1
    end
  end

  defp broadcast_updates(device_id) do
    Phoenix.PubSub.broadcast(PubSub, device_topic(device_id), :alarms_updated)
    Phoenix.PubSub.broadcast(PubSub, @topic_alarms, :alarms_updated)
  end

  defp find_device_id(%ObjectIdentifier{type: :device, instance: instance}, _source), do: instance

  defp find_device_id(_initiating, source) do
    Enum.find_value(Discovery.list_devices(), fn dev ->
      if dev.address == source, do: dev.id
    end)
  end

  defp fetch_device(device_id) do
    case Discovery.get_device(device_id) do
      {:ok, device} -> {:ok, device}
      :error -> {:error, :device_not_found}
    end
  end

  defp device_topic(device_id), do: "device:#{device_id}:alarms"
end
