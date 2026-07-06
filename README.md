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

## Desktop app -experimental- (optional)

BacView can also run as a native desktop app via [elixir-desktop](https://github.com/elixir-desktop/desktop). The web workflow above stays the default.

Desktop mode is selected at **compile time** with `BACVIEW_DESKTOP=1`. Run `mix clean` when switching between web and desktop builds.

**Requirements:** Erlang/OTP with wxWidgets support (see the [desktop getting started guide](https://github.com/elixir-desktop/desktop/blob/main/guides/getting_started.md)). Build installers on native Linux or Windows (msys2 for Windows).

For recent Debian-based installations:
```bash
sudo apt install inotify-tools libtool automake libgmp-dev make \
     libwxgtk-webview3.2-dev libssl-dev libncurses-dev curl git \
     libwxgtk3.2-dev libgtk-3-dev pkg-config -y
```

For adsf/mise builds: Erlang build must be installed after installing the packages above.

Starting the desktop application:

```bash
BACVIEW_DESKTOP=1 mix deps.get
BACVIEW_DESKTOP=1 mix desktop.server
```

Package a distributable installer (`.run` on Linux, `.exe` on Windows):

```bash
mix desktop_installer
```

Desktop notes:

- Settings persist under `~/.config/bacview/runtime_settings.json`
- OS locale is detected on first launch (`Desktop.identify_default_locale/1`); DE/EN can still be switched in the app
- MS/TP will be included if the dependency `circuits_uart` is present or non-Windows OS - typically it will be omitted on Windows (due to NIF)

Verify desktop dependencies: `BACVIEW_DESKTOP=1 mix bacview.desktop.check`

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP port |
| `PHX_SERVER` | — | Set `true` to start HTTP in releases |
| `SECRET_KEY_BASE` | — | Required in production (see `mix phx.gen.secret`) |
| `BACVIEW_BACSTACK_DEBUG` | — | Enable verbose bacstack debug logs (`1` / `true`) |
| `BACVIEW_ENABLE_MSTP` | - | Enable MS/TP transport regardless of platform (`1` / `true`) |
| `BACVIEW_DESKTOP` | — | Set to `1` at compile time to build the desktop app (see above) |
| `BACVIEW_SETTINGS_PATH` | `priv/runtime_settings.json` | Optional override for persisted stack settings |

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
├── BacView.BACnet.Stack          # bacstack client (IPv4/MSTP transport)
├── BacView.Settings
├── BacView.BACnet.Discovery
├── BacView.BACnet.SubscriptionManager
├── BacView.BACnet.AlarmEvent
└── BacView.BACnet.DeviceSessionSupervisor
```

**Transports:** `BacView.BACnet.Transport.IPv4` is production-ready. `BacView.BACnet.Transport.MSTP` is available,
but considered experimental. `BacView.BACnet.Transport.BACnetSC` is a documented stub for future BACnet/SC support.

## Tests

```bash
mix test
mix precommit   # compile, format check, unused deps
```

BACnet is disabled in test (`config/test.exs`: `start_bacnet: false`) to avoid UDP port conflicts.

## License

See project license.
