# BacView

BACnet explorer built in Elixir with Phoenix LiveView and [bacstack](https://github.com/bacnet-ex/bacstack).

Discover devices, browse Structured View hierarchies or create your own based upon object names,
read and write properties, subscribe to COV updates, and monitor alarms — all in real time from the browser.

This project has been built with Grok Build and the Composer 2.5 Fast model.

## Features

- **Network discovery** — Who-Is / I-Am scan with live device list, filters, and optional limited instance / vendor ranges
- **BBMD / Foreign Device** — register with a remote BBMD so Who-Is is distributed via Distribute-Broadcast-To-Network; automatic re-registration
- **Stack settings** — transport (BACnet/IP or MS/TP), network interface / serial port, local device instance, APDU/timeout options; persisted to `runtime_settings.json` and restartable from the UI
- **Device load & scan** — full device object list scan with progress banner; scan recovery for validation failures (relaxed value/type skip modes)
- **Hierarchies** — Structured View tree with search and “reveal in flat list”; optional **name-based hierarchy** built from object-name separators when no Structured View exists
- **Object explorer** — property table with RPM (ReadPropertyMultiple) first, individual ReadProperty fallback, live load progress, status-flag icons, and COV badges
- **Property writes** — Present_Value (with priority where applicable), generic property write, and weekly schedule editor
- **COV subscriptions** — per-property or bulk Present_Value subscribe, auto-renewal, active-subscription overview, notification log, and COV history charts (CSV/JSON export)
- **Alarms & events** — GetAlarmSummary polling, live Confirmed/UnconfirmedEventNotification handling, active-alarm popups, notification-class recipient enrollment, JSON/CSV event export
- **Trend logs** — chart viewer for log buffer data, time-range navigation, CSV/JSON export
- **File objects** — AtomicReadFile / AtomicWriteFile transfer UI
- **EDE export** — generate BACnet Engineering Data Exchange files from a scanned device (`bacnet_ede`)
- **Device services** — time synchronization, DeviceCommunicationControl, and ReinitializeDevice
- **i18n** — German (default) and English via Gettext; locale switcher persisted in `localStorage` (desktop: OS locale on first launch)
- **Keyboard shortcuts** — press `?` for help (`/`, `r`, `1`–`4`, `0` / Escape on device pages)
- **Desktop app (experimental)** — optional native window via elixir-desktop (`BACVIEW_DESKTOP=1`)

## Requirements

- Elixir ~> 1.18
- Erlang/OTP 26+
- Node.js (asset bundling in dev)
- UDP port **47808** available for BACnet/IP (others choosable)

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
| `PHX_SERVER` | — | Set `true` to start HTTP in releases |
| `PORT` | `4000` | HTTP port |
| `SECRET_KEY_BASE` | — | Required in production (see `mix phx.gen.secret`) |
| `BACVIEW_BACSTACK_DEBUG` | — | Enable verbose bacstack debug logs (`1` / `true`) |
| `BACVIEW_ENABLE_MSTP` | - | Enable MS/TP transport regardless of platform (`1` / `true`) |
| `BACVIEW_DESKTOP` | — | Set to `1` at compile time to build the desktop app (see above) |
| `BACVIEW_PROPERTY_READ_CONCURRENCY` | `8` | Max parallel individual `ReadProperty` requests when loading object properties / scan fallback. Lower (e.g. `1`) if old devices are overwhelmed |
| `BACVIEW_SETTINGS_PATH` | `priv/runtime_settings.json` | Optional override for persisted stack settings |
| `BACVIEW_TIMEZONE` | `Europe/Zurich` | IANA timezone for BACnet wall-clock timestamps, bacstack, and UI display |

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

### Supervision tree

```
BacView.Application
├── BacViewWeb.Telemetry
├── BacView.PubSub
├── BacView.Settings                    # runtime_settings.json
├── BacView.BACnet.Cache                # named ETS tables
├── BacView.BACnet.Stack                # Boot + optional Runtime (client/transport)
├── BacView.BACnet.ForeignRegistration  # BBMD foreign device re-registration
├── BacView.BACnet.Discovery            # Who-Is / I-Am
├── BacView.BACnet.SubscriptionManager  # COV subscribe / renew / log
├── BacView.BACnet.NotificationClassRecipient
├── BacView.BACnet.AlarmEvent           # GetAlarmSummary + event notifications
├── BacView.BACnet.DeviceRegistry       # Registry for per-device sessions
├── BacView.BACnet.DeviceSessionSupervisor  # DynamicSupervisor → DeviceSession
└── BacViewWeb.Endpoint
    # (+ Desktop.Window when BACVIEW_DESKTOP=1)
```

BACnet children (Cache through DeviceSessionSupervisor) start only when
`config :bacview, start_bacnet: true` (the default). Tests set `start_bacnet: false`.
The stack transport/client is started after the supervisor boots via
`Stack.Boot.start_runtime/0` so invalid settings leave the app up with BACnet offline.

### Layers

| Layer | Modules | Role |
|-------|---------|------|
| Stack / transport | `Stack`, `Stack.Boot` / `Runtime`, `Transport.*`, `Client` | bacstack client, IPv4/MS/TP, BBMD foreign registration |
| Discovery | `Discovery`, `IAmCollector` | Who-Is / I-Am, device list in ETS |
| Per-device session | `DeviceSession`, `DeviceSessionSupervisor` | Load/scan device, object cache, property read/write, scan recovery |
| Property IO | `PropertyLoad`, `Protocol.PropertyReader`, `ObjectScanRead` | RPM first, individual ReadProperty fallback, scan fallback on hard errors |
| Validation recovery | `ValidationSkipStore` | Persist skip modes after scan recovery |
| Subscriptions / COV | `SubscriptionManager` | COV subscribe, notification log, pruning |
| Alarms | `AlarmEvent`, `ActiveAlarms` | Event state, active-alarm lists |
| Hierarchy | `HierarchyBuilder`, `NameHierarchyBuilder`, `HierarchySplit` | Structured View + name-split trees |
| Web | `BacViewWeb.Live.*`, components | LiveViews, tables, popups, charts |

Primary UI routes:

| Path | LiveView |
|------|----------|
| `/` | `DashboardLive` |
| `/devices/:device_id` | `DeviceLive` |
| `/devices/:device_id/objects/:type/:instance` | `ObjectLive` |

Domain logic lives under `lib/bac_view/bacnet/`; UI under `lib/bac_view_web/`. Runtime BACnet state uses **ETS** (`BacView.BACnet.Cache`) and JSON settings (`BacView.Settings`) — no Ecto for domain data.

### Device load vs object property load

**Full device scan** (`DeviceSession` load/reload): device object → object list → per-object scan → hierarchy. Progress on PubSub `"device:#{id}:load_progress"`.

**Single-object properties** (`DeviceSession.read_properties` → `PropertyLoad` → `PropertyReader`):

1. Prefer RPM (`read_object` / ReadPropertyMultiple).
2. On segmentation/buffer-style failures → individual concurrent `ReadProperty` (default concurrency **8**, `BACVIEW_PROPERTY_READ_CONCURRENCY`).
3. Validation skip mode (from scan recovery) is applied via bacstack `object_opts` on the normal path — it does not force the scan path alone.
4. On certain hard failures → `ObjectScanRead` fallback.

Individual property progress is broadcast on `"device:#{id}:properties_progress"` and shown in the object detail UI.

### ETS tables

Owned by `BacView.BACnet.Cache`:

`:bacview_devices`, `:bacview_objects`, `:bacview_properties`, `:bacview_subscriptions`,
`:bacview_hierarchy`, `:bacview_name_hierarchy`, `:bacview_events`, `:bacview_validation_skip_modes`

Web code must not open subscription ETS directly — use `SubscriptionManager` APIs.

### Transports

| Module | Status |
|--------|--------|
| `BacView.BACnet.Transport.IPv4` | Production-ready (BACnet/IP UDP) |
| `BacView.BACnet.Transport.MSTP` | Available when `circuits_uart` / MS/TP stack is present; experimental |
| `BacView.BACnet.Transport.BACnetSC` | Stub for future BACnet/SC (WebSocket) |

Transport selection and network interface are configured in the dashboard sidebar (persisted settings).

## Tests

```bash
mix precommit   # unlock unused deps, compile -Werror, format, credo, dialyzer, test
```

BACnet is disabled in test (`config/test.exs`: `start_bacnet: false`) to avoid UDP port conflicts.

## License

See project license.
