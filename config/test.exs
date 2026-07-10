import Config

config :bacview, :desktop_mode, false
config :bacview, :mstp_enabled, true
config :bacview, start_bacnet: false

config :bacview,
  runtime_settings_path: Path.expand("../tmp/test_runtime_settings.json", __DIR__)

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bacview, BacViewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BPEhPozJWZC4B4NlNzi9zHtNT+hVjOveptnA/Yptqyy/D4GXCGSDnVzA73AsAJ+Z",
  server: false

# Print warnings and errors during test (capture_log only where a test expects log output).
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
