# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

desktop_mode? = System.get_env("BACVIEW_DESKTOP") in ~w(1 true yes)
windows? = match?({:win32, _}, :os.type())

mstp_enabled =
  case System.get_env("BACVIEW_ENABLE_MSTP") do
    nil ->
      Code.ensure_loaded?(Circuits.UART) or not windows?

    str ->
      str in ~w(1 true yes)
  end

config :bacview, :desktop_mode, desktop_mode?
config :bacview, :mstp_enabled, mstp_enabled

config :bacview, BacViewWeb.Gettext,
  locales: ~w(de en),
  default_locale: "de"

# Configures the endpoint
config :bacview, BacViewWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BacViewWeb.ErrorHTML, json: BacViewWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BacView.PubSub,
  live_view: [signing_salt: "bVXotZo6"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bacview: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  bacview: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure codepagex
config :codepagex, :encodings, [
  :ascii,
  :iso_8859_1,
  "VENDORS/MICSFT/PC/CP850",
  "VENDORS/MICSFT/WINDOWS/CP932"
]

# Enable debug logging paths in the bacstack library (actual output is still
# controlled at runtime via Logger application level, see BacView.Application).
config :bacstack, :debug, true

# Timezone for BACnet wall-clock timestamps and UI display (IANA name).
default_timezone = "Europe/Zurich"

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :bacview, :timezone, default_timezone
config :bacstack, :default_timezone, default_timezone

# Parallel individual ReadProperty streams (object open / scan fallback).
# Historical healthy default is 8. Lower (e.g. 1) if old devices are overwhelmed.
config :bacview, :property_read_concurrency, 8

# WAGO proprietary properties
config :bacstack, :additional_property_identifiers,
  device_uuid: 507,
  timezone_string: 516,
  timezone: 517,
  time_before_operation: 518,
  loop_enable: 523,
  loop_mode: 524

# WAGO proprietary properties
config :bacstack, :objects_additional_properties,
  device:
    (quote do
       # Intrinsic Reporting was added in 135-2016
       # services(intrinsic: true)

       field(:device_uuid, binary(),
         annotation: [decoder: fn %{value: value} -> Base.encode16(value) end]
       )

       field(:timezone_string, String.t())
       field(:timezone, String.t())
     end),
  loop:
    (quote do
       field(:loop_enable, boolean(), encode_as: :enumerated)

       field(:loop_mode, :bacnet_loop | :plc_loop,
         bac_type: {:in_list, [:bacnet_loop, :plc_loop]},
         annotation: [
           encoder: &{:enumerated, if(&1 == :plc_loop, do: 1, else: 0)},
           decoder: &if(&1.value == 1, do: :plc_loop, else: :bacnet_loop)
         ]
       )
     end),
  schedule:
    (quote do
       field(:time_before_operation, non_neg_integer())
     end)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

if desktop_mode? do
  import_config "desktop.exs"
end
