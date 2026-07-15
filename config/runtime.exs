import Config

timezone =
  System.get_env("BACVIEW_TIMEZONE") ||
    Application.get_env(:bacview, :timezone, "Europe/Zurich")

config :bacview, :timezone, timezone
config :bacstack, :default_timezone, timezone

property_read_concurrency =
  case System.get_env("BACVIEW_PROPERTY_READ_CONCURRENCY") do
    nil ->
      Application.get_env(:bacview, :property_read_concurrency, 8)

    raw ->
      case Integer.parse(raw) do
        {n, ""} when n > 0 -> n
        _invalid -> Application.get_env(:bacview, :property_read_concurrency, 8)
      end
  end

property_read_concurrency_disable_shared_reduction =
  case System.get_env("BACVIEW_READ_CONCUR_DISABLE_SHARED_RED") do
    nil ->
      false

    raw ->
      raw in ~w(1 true yes)
  end

config :bacview, :property_read_concurrency, property_read_concurrency

config :bacview,
       :property_read_concurrency_disable_shared_reduction,
       property_read_concurrency_disable_shared_reduction

if Application.get_env(:bacview, :desktop_mode) do
  {:ok, [[home]]} = :init.get_argument(:home)

  config :bacview,
         :runtime_settings_path,
         Path.join([List.to_string(home), ".config", "bacview", "runtime_settings.json"])
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/bacview start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :bacview, BacViewWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :bacview, BacViewWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [
      ip: {127, 0, 0, 1},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :bacview, BacViewWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :bacview, BacViewWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
