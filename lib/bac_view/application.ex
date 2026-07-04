defmodule BacView.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    configure_bacstack_logging()

    bacnet_children =
      if Application.get_env(:bacview, :start_bacnet, true) do
        [
          {Registry, keys: :unique, name: BacView.BACnet.DeviceRegistry},
          BacView.BACnet.Cache,
          BacView.BACnet.Stack,
          BacView.BACnet.ForeignRegistration,
          BacView.BACnet.Discovery,
          BacView.BACnet.SubscriptionManager,
          BacView.BACnet.NotificationClassRecipient,
          BacView.BACnet.AlarmEvent,
          BacView.BACnet.DeviceSessionSupervisor
        ]
      else
        []
      end

    # credo:disable-for-lines:10 Credo.Check.Refactor.AppendSingleItem
    children =
      [
        BacViewWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:bacview, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BacView.PubSub},
        BacView.Settings
      ] ++
        bacnet_children ++
        [BacViewWeb.Endpoint]

    opts = [strategy: :one_for_one, name: BacView.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = ok ->
        maybe_start_bacnet_runtime()
        ok

      other ->
        other
    end
  end

  defp maybe_start_bacnet_runtime() do
    if Application.get_env(:bacview, :start_bacnet, true) do
      case BacView.BACnet.Stack.Boot.start_runtime() do
        :ok ->
          :ok

        {:error, reason} ->
          require Logger
          Logger.warning("BACnet stack is offline until settings are fixed: #{inspect(reason)}")
      end
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    BacViewWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # By default, suppress verbose debug logs from the bacstack library.
  # Pass --bacstack-debug (or set BACSTACK_DEBUG=1) at startup to enable them.
  defp configure_bacstack_logging() do
    args =
      System.argv() ++
        Enum.map(:init.get_plain_arguments(), &to_string/1)

    enabled? =
      "--bacstack-debug" in args or
        System.get_env("BACSTACK_DEBUG") in ["1", "true", "yes"] or
        System.get_env("BACVIEW_BACSTACK_DEBUG") in ["1", "true", "yes"]

    level = if enabled?, do: :debug, else: :info
    Logger.put_application_level(:bacstack, level)
  end
end
