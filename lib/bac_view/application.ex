defmodule BacView.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    load_all_bacstack_modules()
    configure_bacstack_logging()
    maybe_configure_desktop_locale()
    maybe_init_desktop_session_table()

    session_children = [
      {Registry, keys: :unique, name: BacView.BACnet.DeviceRegistry},
      BacView.BACnet.DeviceSessionSupervisor
    ]

    bacnet_children =
      if Application.get_env(:bacview, :start_bacnet, true) do
        [
          BacView.BACnet.Cache,
          BacView.BACnet.Stack,
          BacView.BACnet.ForeignRegistration,
          BacView.BACnet.Discovery,
          BacView.BACnet.SubscriptionManager,
          BacView.BACnet.NotificationClassRecipient,
          BacView.BACnet.AlarmEvent
        ] ++ session_children
      else
        session_children
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
        [BacViewWeb.Endpoint] ++
        desktop_window_children()

    opts = [strategy: :one_for_one, name: BacView.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = ok ->
        maybe_start_bacnet_runtime()
        ok

      other ->
        other
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    BacViewWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  if Application.compile_env(:bacview, :desktop_mode) do
    defp maybe_configure_desktop_locale() do
      Desktop.identify_default_locale(BacViewWeb.Gettext)

      detected =
        Application.get_env(:gettext, :default_locale) ||
          Application.get_env(:bacview, BacViewWeb.Gettext)[:default_locale] ||
          "de"

      Application.put_env(:bacview, BacViewWeb.Gettext, default_locale: detected)
      Gettext.put_locale(BacViewWeb.Gettext, detected)
    end

    defp maybe_init_desktop_session_table() do
      :ets.new(:bacview_session, [:named_table, :public, read_concurrency: true])
    end

    defp desktop_window_children() do
      # Get screen size
      wx_display = :wxDisplay.new()
      {_size_x, _size_y, size_w, size_h} = :wxDisplay.getClientArea(wx_display)
      :wxDisplay.destroy(wx_display)

      [
        {Desktop.Window,
         [
           app: :bacview,
           id: BacViewWindow,
           title: "BacView",
           size: {trunc(size_w * 0.9), trunc(size_h * 0.9)},
           icon: "static/icon.png",
           url: &BacViewWeb.Endpoint.url/0
         ]}
      ]
    end
  else
    defp maybe_configure_desktop_locale(), do: :ok
    defp maybe_init_desktop_session_table(), do: :ok
    defp desktop_window_children(), do: []
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

  # We need to make sure all bacstack modules are loaded in :prod
  # So we just do it always, it doesn't hurt us
  defp load_all_bacstack_modules() do
    {:ok, modules} = :application.get_key(:bacstack, :modules)

    for module <- modules do
      Code.ensure_loaded(module)
    end
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
