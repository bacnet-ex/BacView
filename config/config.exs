# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bacview,
  generators: [timestamp_type: :utc_datetime]

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

# Enable debug logging paths in the bacstack library (actual output is still
# controlled at runtime via Logger application level, see BacView.Application).
config :bacstack, :debug, true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
