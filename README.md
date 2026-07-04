# BacView

Standalone bilingual BACnet explorer (German primary) built with Elixir, Phoenix LiveView, and [bacstack](https://github.com/bacnet-ex/bacstack).

Discover devices, browse Structured View hierarchies, read properties, subscribe to COV updates, and monitor alarms/events — all in real time from the browser.

This project has been built with Grok Build and the Composer 2.5 Fast model.

## Features

- **Network discovery** — Who-Is / I-Am scan with device list
- **Structured View** — hierarchy tree with search and flat-list reveal
- **Object explorer** — property reads (chunked RPM), live COV badges
- **COV subscriptions** — per-property subscribe, bulk Present_Value subscribe, auto-renewal
- **Alarms & events** — GetEventInformation polling, live event notifications, JSON/CSV export
- **i18n** — German (default) and English, persisted in `localStorage`
- **Keyboard shortcuts** — press `?` for help (`/`, `r`, `1`–`4` on device pages)

## Requirements

- Elixir ~> 1.18
- Erlang/OTP 26+
- Node.js (asset bundling in dev)
- UDP port **47808** available for BACnet/IP

## Quick start (development)

```bash
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000), click **Netzwerk scannen**, then select a device.

To discover devices on a **remote BACnet/IP network**, register BacView as a Foreign Device with your BBMD (dashboard sidebar). Who-Is scans are then distributed through the BBMD.

**Stack settings** (transport, network interface, device instance, COV options, BBMD) are configured in the dashboard sidebar and persisted to `priv/runtime_settings.json`.

Copy `.env.example` to `.env` and adjust as needed (optional in dev).

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP port |
| `PHX_SERVER` | — | Set `true` to start HTTP in releases |
| `SECRET_KEY_BASE` | — | Required in production (see `mix phx.gen.secret`) |
| `BACVIEW_SETTINGS_PATH` | `priv/runtime_settings.json` | Optional override for persisted stack settings |
| `BACVIEW_BACSTACK_DEBUG` | — | Enable verbose bacstack debug logs (`1` / `true`) |

## Production release

```bash
mix assets.deploy
SECRET_KEY_BASE=$(mix phx.gen.secret) mix release
```

Start the release:

```bash
PHX_SERVER=true PORT=4000 ./_build/bacview/rel/bacview/bin/server
```

Or use the release binary directly:

```bash
PHX_SERVER=true ./_build/bacview/rel/bacview/bin/bacview start
```

Place a `.env` file next to the release root to load environment variables at startup (see `rel/env.sh.eex`).

## Architecture

```
BacView.Application
├── BacViewWeb.Endpoint
├── BacView.PubSub
├── BacView.BACnet.Cache          # ETS tables
├── BacView.BACnet.Stack          # bacstack client (IPv4 transport)
├── BacView.Settings
├── BacView.BACnet.Discovery
├── BacView.BACnet.SubscriptionManager
├── BacView.BACnet.AlarmEvent
└── BacView.BACnet.DeviceSessionSupervisor
```

**Transports:** `BacView.BACnet.Transport.IPv4` is production-ready. `BacView.BACnet.Transport.BACnetSC` is a documented stub for future BACnet/SC support.

## Tests

```bash
mix test
mix precommit   # compile, format check, unused deps
```

BACnet is disabled in test (`config/test.exs`: `start_bacnet: false`) to avoid UDP port conflicts.

## License

See project license.
