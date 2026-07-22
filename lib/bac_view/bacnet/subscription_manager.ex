defmodule BacView.BACnet.SubscriptionManager do
  @moduledoc """
  Central COV subscription tracking, notification routing, and renewal.
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.APDU.ConfirmedServiceRequest
  alias BACnet.Protocol.APDU.SimpleACK
  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PropertyValue
  alias BACnet.Protocol.Services.ConfirmedCovNotification
  alias BACnet.Protocol.Services.UnconfirmedCovNotification
  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Client
  alias BacView.BACnet.DeviceSession
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.NotificationLogLimit
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Subscription

  @table :bacview_subscriptions
  @notification_log :bacview_cov_notification_log
  @notification_seq :bacview_cov_notification_seq
  @topic_cov "cov:updates"
  # Device restart unsolicited COV (ASHRAE 135): must include all three.
  @restart_cov_property_atoms [:system_status, :time_of_device_restart, :last_restart_reason]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec subscribe(integer(), ObjectIdentifier.t(), atom() | integer(), keyword()) ::
          :ok | {:error, term()}
  def subscribe(device_id, object_id, property \\ :present_value, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe, device_id, object_id, property, opts}, 30_000)
  end

  @spec unsubscribe(integer(), ObjectIdentifier.t(), atom() | integer()) ::
          :ok | {:error, term()}
  def unsubscribe(device_id, object_id, property \\ :present_value) do
    GenServer.call(__MODULE__, {:unsubscribe, device_id, object_id, property})
  end

  @spec list_active(integer() | nil) :: [map()]
  def list_active(device_id \\ nil) do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, sub} -> sub end)
      |> maybe_filter_device(device_id)
      |> Enum.sort_by(&{&1.device_id, &1.object_id.type, &1.object_id.instance, &1.property})
    end
  end

  @spec active_count(integer() | nil) :: non_neg_integer()
  def active_count(device_id \\ nil) do
    length(list_active(device_id))
  end

  @spec subscribed?(integer(), ObjectIdentifier.t(), atom() | integer()) :: boolean()
  def subscribed?(device_id, object_id, property \\ :present_value) do
    key = Subscription.key(device_id, object_id, property)
    :ets.whereis(@table) != :undefined and :ets.member(@table, key)
  end

  @spec list_notifications(integer()) :: [map()]
  def list_notifications(device_id) do
    if :ets.whereis(@notification_log) == :undefined do
      []
    else
      @notification_log
      |> :ets.tab2list()
      |> Enum.filter(fn {{dev_id, _type, _instance, _property, _neg_micro, _seq}, _entry} ->
        dev_id == device_id
      end)
      |> Enum.sort_by(
        fn {{_device_id, _type, _instance, _property, neg_micro, seq}, _entry} ->
          {neg_micro, seq}
        end,
        :asc
      )
      |> Enum.map(fn {_key, entry} -> entry end)
    end
  end

  @spec subscribe_all_present_values(integer(), pid()) :: :ok
  def subscribe_all_present_values(device_id, progress_pid) do
    GenServer.cast(__MODULE__, {:subscribe_all_pv, device_id, progress_pid})
  end

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
    schedule_renewal()

    {:ok, %{bulk_tasks: %{}}}
  end

  @impl true
  def handle_call({:subscribe, device_id, object_id, property, opts}, _from, state) do
    result = do_subscribe(device_id, object_id, property, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:unsubscribe, device_id, object_id, property}, _from, state) do
    result = do_unsubscribe(device_id, object_id, property)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:subscribe_all_pv, device_id, progress_pid}, state) do
    objects =
      Enum.filter(DeviceSession.objects(device_id), &(not is_nil(&1.present_value)))

    total = length(objects)

    Task.start(fn ->
      objects
      |> Enum.with_index(1)
      |> Enum.each(fn {obj, idx} ->
        object_id = %ObjectIdentifier{type: obj.type, instance: obj.instance}

        _handle_cast = subscribe(device_id, object_id, :present_value)

        send(progress_pid, {:cov_bulk_progress, idx, total})
      end)

      send(progress_pid, {:cov_bulk_done, total})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:renew_subscriptions, state) do
    schedule_renewal()
    now = DateTime.utc_now()

    if :ets.whereis(@table) != :undefined do
      for {_key, sub} <- :ets.tab2list(@table), Subscription.needs_renewal?(sub, now) do
        renew_subscription(sub)
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:bacnet_client, ref, apdu, {source, _bvlc, _npci}, client_pid},
        state
      ) do
    case apdu do
      %UnconfirmedServiceRequest{} = req ->
        case UnconfirmedServiceRequest.to_service(req) do
          {:ok, %UnconfirmedCovNotification{} = notif} ->
            handle_cov_notification(notif, source, ref, client_pid, false)

          _renew_subscriptions ->
            :ok
        end

      %ConfirmedServiceRequest{invoke_id: invoke_id} = req ->
        case ConfirmedServiceRequest.to_service(req) do
          {:ok, %ConfirmedCovNotification{} = notif} ->
            handle_cov_notification(notif, source, ref, client_pid, true, invoke_id)

          _renew_subscriptions ->
            :ok
        end

      _renew_subscriptions ->
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
  def handle_info(:resubscribe_all_active, state) do
    if :ets.whereis(@table) != :undefined do
      @table
      |> :ets.tab2list()
      |> Enum.each(fn {_key, sub} -> renew_subscription(sub) end)
    end

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

  @doc false
  @spec cov_property_fallback?(term()) :: boolean()
  def cov_property_fallback?({:bacnet_error, %APDU.Error{code: code}})
      when code in [:optional_functionality_not_supported, :not_cov_property],
      do: true

  def cov_property_fallback?({:bacnet_reject, %APDU.Reject{reason: reason}})
      when reason in [:reject_unrecognized_service, :unrecognized_service],
      do: true

  def cov_property_fallback?(_reason), do: false

  @doc """
  True when an unconfirmed COV reports a device restart.

  Unsolicited restart notifications use subscriber process identifier `0` and
  time remaining `0`, target the device object, and carry `system_status`,
  `time_of_device_restart`, and `last_restart_reason`.
  """
  @spec device_restart_cov_notification?(term()) :: boolean()
  def device_restart_cov_notification?(%UnconfirmedCovNotification{
        process_identifier: 0,
        time_remaining: 0,
        initiating_device: %ObjectIdentifier{type: :device, instance: init_inst},
        monitored_object: %ObjectIdentifier{type: :device, instance: mon_inst},
        property_values: property_values
      })
      when init_inst == mon_inst and is_list(property_values) do
    restart_cov_properties_present?(property_values)
  end

  def device_restart_cov_notification?(_notification), do: false

  @doc false
  @spec unknown_object_error?(term()) :: boolean()
  def unknown_object_error?({:bacnet_error, %APDU.Error{code: :unknown_object}}), do: true
  def unknown_object_error?(%APDU.Error{code: :unknown_object}), do: true
  def unknown_object_error?(:unknown_object), do: true
  def unknown_object_error?({:error, reason}), do: unknown_object_error?(reason)
  def unknown_object_error?(_reason), do: false

  @doc """
  Re-subscribes all active COV entries for `device_id`.

  Subscriptions that fail with `:unknown_object` are removed from local tracking
  (object no longer exists after a device restart / reconfiguration).
  """
  @spec renew_device_subscriptions(integer()) :: :ok
  def renew_device_subscriptions(device_id) when is_integer(device_id) do
    device_id
    |> list_active()
    |> Enum.each(&renew_subscription/1)

    :ok
  end

  @doc """
  Handles a device-restart unconfirmed COV: ensure discovery entry (Who-Is/I-Am
  for unknown devices + scan-panel filters), optionally force-scan, then renew
  active COV subscriptions for that device.

  Options:
  * `:async` (default `true`) — run ensure + scan + renew off the COV process
    (Who-Is wait must not block the SubscriptionManager mailbox)
  * `:scan` (default `Settings.scan_on_online?()`) — force device reload/load
  """
  @spec handle_device_restart_cov(UnconfirmedCovNotification.t(), term(), keyword()) :: :ok
  def handle_device_restart_cov(%UnconfirmedCovNotification{} = notification, source, opts \\ []) do
    if device_restart_cov_notification?(notification) do
      scan? = Keyword.get(opts, :scan, BacView.Settings.scan_on_online?())
      async? = Keyword.get(opts, :async, true)
      run_restart_recovery(notification.initiating_device, source, scan?, async?)
    end

    :ok
  end

  @doc false
  @spec apply_renew_result(map(), :ok | {:error, term()}) :: :ok | {:error, term()}
  def apply_renew_result(sub, :ok) when is_map(sub), do: :ok

  def apply_renew_result(sub, {:error, reason}) when is_map(sub) do
    if unknown_object_error?(reason) do
      remove_local_subscription(sub, reason)
      :ok
    else
      Logger.warning(
        "COV renewal failed for device #{sub.device_id} " <>
          "#{inspect(sub.object_id)} #{inspect(sub.property)}: #{inspect(reason)}"
      )

      {:error, reason}
    end
  end

  @doc false
  @spec resubscribe_all_active() :: :ok
  def resubscribe_all_active() do
    if Process.whereis(__MODULE__) do
      send(__MODULE__, :resubscribe_all_active)
    end

    :ok
  end

  defp run_restart_recovery(device_object, source, scan?, true = _async?) do
    Task.start(fn -> run_restart_recovery(device_object, source, scan?, false) end)
    :ok
  end

  defp run_restart_recovery(
         %ObjectIdentifier{type: :device, instance: device_id} = device_object,
         source,
         scan?,
         false = _async?
       ) do
    case Discovery.ensure_discovered_device(device_object, source) do
      {:ok, _device} ->
        if scan? do
          force_scan_after_restart(device_id)
        end

        renew_device_subscriptions(device_id)

      :error ->
        Logger.debug(
          "Restart COV for device #{device_id} ignored: device not accepted " <>
            "(Who-Is/I-Am probe or scan panel filters)"
        )
    end

    :ok
  end

  defp force_scan_after_restart(device_id) do
    if DeviceSession.loading?(device_id) do
      # Join in-flight load so renew uses a consistent session afterwards.
      _load_result = DeviceSession.load(device_id)
    else
      case DeviceSession.reload(device_id) do
        {:ok, _loaded} ->
          Logger.info("Scanned device #{device_id} after restart COV")

        {:error, reason} ->
          Logger.debug(
            "Scan after restart COV failed for device #{device_id}: #{inspect(reason)}"
          )
      end
    end
  end

  defp renew_subscription(sub) do
    result =
      do_subscribe(sub.device_id, sub.object_id, sub.property,
        lifetime: sub.lifetime,
        confirmed: sub.confirmed,
        process_id: sub.process_id,
        subscribe_service: Map.get(sub, :subscribe_service, :subscribe_cov_property)
      )

    apply_renew_result(sub, result)
  end

  defp remove_local_subscription(sub, reason) do
    key = Subscription.key(sub.device_id, sub.object_id, sub.property)

    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, key)
    end

    Logger.info(
      "Removed COV subscription for device #{sub.device_id} " <>
        "#{inspect(sub.object_id)} #{inspect(sub.property)} " <>
        "(unknown object after renew: #{inspect(reason)})"
    )

    broadcast_cov_meta()
    :ok
  end

  defp do_subscribe(device_id, object_id, property, opts) do
    settings = BacView.Settings.get()
    lifetime = Keyword.get(opts, :lifetime, settings.cov_lifetime_seconds)
    confirmed = Keyword.get(opts, :confirmed, settings.cov_confirmed)
    process_id = Keyword.get(opts, :process_id, Subscription.process_id())

    sub_opts =
      [
        lifetime: lifetime,
        confirmed: confirmed,
        pid: process_id
      ] ++ cov_increment_opt(settings)

    preferred_service = Keyword.get(opts, :subscribe_service, :subscribe_cov_property)

    with {:ok, device} <- fetch_device(device_id),
         {:ok, subscribe_service} <-
           send_subscribe(
             device.address,
             object_id,
             property,
             device_id,
             sub_opts,
             preferred_service
           ) do
      cov_increment =
        if subscribe_service == :subscribe_cov_property,
          do: Keyword.get(sub_opts, :cov_increment),
          else: nil

      sub =
        Subscription.build(device_id, device.address, object_id, property,
          lifetime: lifetime,
          confirmed: confirmed,
          process_id: process_id,
          cov_increment: cov_increment,
          subscribe_service: subscribe_service
        )

      :ets.insert(@table, {Subscription.key(device_id, object_id, property), sub})
      broadcast_cov_meta()
      :ok
    else
      {:error, _device_id} = err -> err
    end
  end

  defp do_unsubscribe(device_id, object_id, property) do
    {process_id, subscribe_service} =
      case lookup_subscription(device_id, object_id, property) do
        {:ok, sub} ->
          {sub.process_id, Map.get(sub, :subscribe_service, :subscribe_cov_property)}

        :error ->
          {Subscription.process_id(), :subscribe_cov_property}
      end

    with {:ok, device} <- fetch_device(device_id),
         :ok <-
           cancel_subscription(
             device.address,
             object_id,
             property,
             device_id,
             process_id,
             subscribe_service
           ) do
      :ets.delete(@table, Subscription.key(device_id, object_id, property))
      broadcast_cov_meta()
      :ok
    else
      {:error, _device_id} = err -> err
    end
  end

  defp send_subscribe(destination, object_id, property, device_id, opts, preferred_service) do
    opts = Keyword.put(opts, :device_id, device_id)

    case preferred_service do
      :subscribe_cov when property == :present_value ->
        subscribe_present_value(destination, object_id, property, opts, :subscribe_cov)

      _preferred_service ->
        subscribe_present_value(destination, object_id, property, opts, :subscribe_cov_property)
    end
  end

  defp subscribe_present_value(destination, object_id, _property, opts, :subscribe_cov) do
    case cov_client().subscribe_cov(destination, object_id, opts) do
      :ok -> {:ok, :subscribe_cov}
      {:error, _reason} = err -> err
    end
  end

  defp subscribe_present_value(destination, object_id, property, opts, :subscribe_cov_property) do
    case cov_client().subscribe_cov_property(destination, object_id, property, opts) do
      :ok ->
        {:ok, :subscribe_cov_property}

      {:error, reason} = err ->
        if property == :present_value and cov_property_fallback?(reason) do
          Logger.debug(
            "Subscribe COV Property failed for #{inspect(object_id)}, " <>
              "falling back to Subscribe COV: #{inspect(reason)}"
          )

          subscribe_present_value(destination, object_id, property, opts, :subscribe_cov)
        else
          err
        end
    end
  end

  defp cancel_subscription(
         destination,
         object_id,
         property,
         device_id,
         process_id,
         subscribe_service
       ) do
    opts = [lifetime: nil, pid: process_id, device_id: device_id]

    case subscribe_service do
      :subscribe_cov when property == :present_value ->
        cancel_present_value(destination, object_id, opts, :subscribe_cov)

      _subscribe_service ->
        case cov_client().subscribe_cov_property(destination, object_id, property, opts) do
          :ok ->
            :ok

          {:error, reason} ->
            if property == :present_value and cov_property_fallback?(reason) do
              cancel_present_value(destination, object_id, opts, :subscribe_cov)
            else
              {:error, reason}
            end
        end
    end
  end

  defp cancel_present_value(destination, object_id, opts, :subscribe_cov) do
    cov_client().subscribe_cov(destination, object_id, opts)
  end

  defp cov_client() do
    Application.get_env(:bacview, :cov_client, Client)
  end

  defp handle_cov_notification(notification, source, ref, client_pid, confirmed?, invoke_id \\ 0) do
    device_id = find_device_id(notification.initiating_device, source)
    object_id = notification.monitored_object

    if confirmed? and is_reference(ref) do
      ack = %SimpleACK{invoke_id: invoke_id, service: :confirmed_cov_notification}
      _notification = StackClient.reply(client_pid, ref, ack, [])
    end

    for %PropertyValue{property_identifier: property, property_value: raw_value} <-
          notification.property_values,
        not is_nil(device_id) do
      value = unwrap_cov_value(raw_value)
      formatted = format_cov_value(device_id, object_id, property, value)
      key = Subscription.key(device_id, object_id, property)

      received_now = DateTime.utc_now()

      updated_sub =
        case :ets.lookup(@table, key) do
          [{^key, sub}] ->
            Map.merge(sub, %{
              last_cov_at: received_now,
              last_value: value,
              last_value_formatted: formatted,
              time_remaining: notification.time_remaining,
              expires_at: expires_at_from_notification(notification.time_remaining, received_now)
            })

          [] ->
            nil
        end

      if updated_sub, do: :ets.insert(@table, {key, updated_sub})

      received_at = received_now

      log_entry =
        append_notification(%{
          device_id: device_id,
          object_id: object_id,
          property: property,
          value: value,
          formatted: formatted,
          confirmed: confirmed?,
          time_remaining: notification.time_remaining,
          received_at: received_at
        })

      DeviceSession.apply_cov_update(device_id, object_id, property, value, formatted)

      Phoenix.PubSub.broadcast(
        BacView.PubSub,
        device_topic(device_id),
        {:cov_update,
         %{
           device_id: device_id,
           type: object_id.type,
           instance: object_id.instance,
           property: property,
           value: value,
           formatted: formatted,
           at: received_at
         }}
      )

      Phoenix.PubSub.broadcast(
        BacView.PubSub,
        device_topic(device_id),
        {:cov_notification, log_entry}
      )
    end

    Phoenix.PubSub.broadcast(BacView.PubSub, @topic_cov, :cov_updated)

    if not confirmed? do
      handle_device_restart_cov(notification, source)
    end
  end

  defp restart_cov_properties_present?(property_values) do
    ids = MapSet.new(property_values, & &1.property_identifier)

    Enum.all?(@restart_cov_property_atoms, fn atom ->
      MapSet.member?(ids, atom) or MapSet.member?(ids, property_id_number(atom))
    end)
  end

  defp property_id_number(:system_status), do: 112
  defp property_id_number(:last_restart_reason), do: 196
  defp property_id_number(:time_of_device_restart), do: 203

  defp append_notification(attrs) do
    device_id = Map.fetch!(attrs, :device_id)
    object_id = Map.fetch!(attrs, :object_id)
    property = Map.fetch!(attrs, :property)
    received_at = Map.fetch!(attrs, :received_at)
    seq = next_notification_seq(device_id)
    micro = DateTime.to_unix(received_at, :microsecond)
    key = {device_id, object_id.type, object_id.instance, property, -micro, seq}

    log_entry = Map.put(attrs, :log_id, seq)

    :ets.insert(@notification_log, {key, log_entry})

    subscription_key = Subscription.key(device_id, object_id, property)
    NotificationLogLimit.prune_cov_subscription(@notification_log, subscription_key)
    NotificationLogLimit.prune_cov_device(@notification_log, device_id)

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

  defp lookup_subscription(device_id, object_id, property) do
    key = Subscription.key(device_id, object_id, property)

    case :ets.lookup(@table, key) do
      [{^key, sub}] -> {:ok, sub}
      [] -> :error
    end
  end

  defp maybe_filter_device(subs, nil), do: subs
  defp maybe_filter_device(subs, device_id), do: Enum.filter(subs, &(&1.device_id == device_id))

  defp cov_increment_opt(%{cov_increment: nil}), do: []
  defp cov_increment_opt(%{cov_increment: inc}), do: [cov_increment: inc]

  defp schedule_renewal() do
    interval =
      active_lifetimes()
      |> Enum.min(fn -> BacView.Settings.cov_lifetime() end)
      |> Subscription.renew_check_interval_ms()

    Process.send_after(self(), :renew_subscriptions, interval)
  end

  defp active_lifetimes() do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, %{lifetime: lifetime}} -> lifetime end)
      |> Enum.filter(&(&1 > 0))
    end
  end

  defp expires_at_from_notification(time_remaining, now)
       when is_integer(time_remaining) and time_remaining > 0 do
    DateTime.add(now, time_remaining, :second)
  end

  defp expires_at_from_notification(_time_remaining, now), do: now

  defp broadcast_cov_meta() do
    Phoenix.PubSub.broadcast(BacView.PubSub, @topic_cov, :cov_updated)
  end

  defp device_topic(device_id), do: "device:#{device_id}:cov"

  defp unwrap_cov_value([
         %Encoding{type: :date, value: date},
         %Encoding{type: :time, value: time}
       ]) do
    %BACnetDateTime{date: date, time: time}
  end

  defp unwrap_cov_value(%Encoding{value: value}), do: value
  defp unwrap_cov_value(value), do: value

  defp format_cov_value(device_id, object_id, property, value) do
    obj =
      Enum.find(DeviceSession.objects(device_id), fn o ->
        o.type == object_id.type and o.instance == object_id.instance
      end)

    PropertyFormatter.format_property_value(property, value, obj)
  end
end
