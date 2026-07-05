import Config

config :bacview, BacViewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  server: true,
  check_origin: false
