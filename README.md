# AdGuard Control

**English** · [Polski](README.pl.md)

A native iOS app (Swift / SwiftUI, iOS 17+) for managing your own [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) server from your iPhone, designed for a Raspberry Pi reached over [Tailscale](https://tailscale.com) or your home network.

The API client is written against the official AdGuard Home OpenAPI specification (API v0.107). No endpoint is invented, deprecated endpoints are not used, and there are **no third-party dependencies** (only SwiftUI, Swift Charts, Security.framework and URLSession).

> **Unofficial project.** AdGuard Control is an independent app. It is not affiliated with, endorsed by or sponsored by AdGuard Software Ltd. "AdGuard" and "AdGuard Home" are trademarks of their respective owners.

> **Language note:** the app's user interface is currently in **Polish**. The documentation is in English with a [Polish version](README.pl.md). Localization contributions are welcome.

<p align="center">
  <img src="docs/images/dashboard.png" width="23%" alt="Dashboard">
  <img src="docs/images/protection.png" width="23%" alt="Protection">
  <img src="docs/images/query-log.png" width="23%" alt="Query log">
  <img src="docs/images/filters.png" width="23%" alt="Filters">
</p>

## Features

- **Overview** (Dashboard): protection status, counters (queries, blocked, block rate, clients, response time), activity chart, top domains / blocked domains / clients, pausing protection for 1 min / 10 min / 1 h / 24 h.
- **Protection**: DNS protection, filtering, safe browsing, parental control (on/off), safe search per search engine, blocked services, host checker.
- **Log** (query log): infinite scroll, debounced search, status filters, client filter, details, and quick actions (block / allow / custom rule), also by swipe.
- **Filters**: blocklists and allowlists (add, edit, remove, enable, refresh, update interval), custom rules, DNS rewrites.
- **Clients, DNS, DHCP, TLS, access control, general settings** (statistics and query log retention, clearing statistics/log/cache, server updates).
- **Multiple servers** with a quick switcher; every profile has its own address, login, "Require Tailscale" option and Keychain-stored password.
- **Widgets** (home screen and lock screen) with a one-tap pause button. See [docs/widgets.md](docs/widgets.md).
- **Diagnostics**: when a connection fails, the app shows a checklist (is Tailscale on, is the server online, is the port right).
- Every configuration change asks for confirmation and, where possible, offers **Undo**.

<p align="center">
  <img src="docs/images/servers.png" width="23%" alt="Servers">
  <img src="docs/images/more.png" width="23%" alt="More">
  <img src="docs/images/widgets.png" width="30%" alt="Widgets">
</p>

## Requirements

- Xcode 16 or newer (developed with Xcode 27) and iOS 17+.
- An AdGuard Home server (API v0.107) reachable from your iPhone, ideally over Tailscale. See [docs/tailscale.md](docs/tailscale.md).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project: `brew install xcodegen`.

## Build and run

```bash
git clone https://github.com/nullDEM/adguard-control.git
cd adguard-control
xcodegen generate
open AdGuardControl.xcodeproj
```

Pick the **AdGuardControl** scheme and a simulator, then press ⌘R. Run the tests with ⌘U or:

```bash
xcodebuild -project AdGuardControl.xcodeproj -scheme AdGuardControl \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

To run on a real iPhone you need your own signing setup (Team, bundle identifier, App Group and Keychain sharing). See [docs/development.md](docs/development.md).

## First-time setup in the app

1. On first launch the **New server** screen appears.
2. Enter a profile name, for example "Raspberry Pi".
3. Enter the address, for example `http://100.x.y.z:3000` (Tailscale IP) or a MagicDNS name. The scheme can be omitted (the app adds `http://`); a trailing `/` and `/control` are stripped. The port must match your AdGuard Home web interface. See [the port guide](docs/tailscale.md#web-interface-port-80-3000-or-something-else).
4. Enter your AdGuard Home login and password.
5. Optionally enable **Require Tailscale**: the app then sends no request until the iPhone has an active Tailscale interface.
6. Tap **Test connection**, then **Save**.

## Security at a glance

- Passwords are stored **only in the iOS Keychain**. Profiles in `UserDefaults` hold no secrets. The app never logs passwords or `Authorization` headers.
- Cleartext HTTP is only allowed to private networks, Tailscale and loopback. Public hosts require HTTPS, special addresses (link-local, multicast, `0.0.0.0`) are rejected, and HTTP redirects are never followed.
- TLS validation is never disabled.

Details and the reasoning behind the App Transport Security setting: [docs/security.md](docs/security.md).

## Documentation

| Topic | English | Polski |
|---|---|---|
| Tailscale, ports, Raspberry Pi setup | [docs/tailscale.md](docs/tailscale.md) | [docs/pl/tailscale.md](docs/pl/tailscale.md) |
| Widgets | [docs/widgets.md](docs/widgets.md) | [docs/pl/widgets.md](docs/pl/widgets.md) |
| Security | [docs/security.md](docs/security.md) | [docs/pl/security.md](docs/pl/security.md) |
| Development, testing, signing | [docs/development.md](docs/development.md) | [docs/pl/development.md](docs/pl/development.md) |
| API coverage and known limits | [docs/api-coverage.md](docs/api-coverage.md) | [docs/pl/api-coverage.md](docs/pl/api-coverage.md) |

## Project layout

```
project.yml                   XcodeGen project definition (source of truth)
AdGuardControl/               the app
  App/                        entry point, root view, tab bar, UI-test stub (Debug only)
  Models/                     Codable models matching the OpenAPI spec
  Networking/                 AdGuardAPIClient (async/await, URLSession), APIError
  Storage/                    KeychainStore (passwords), ProfileStore, shared App Group storage
  Utilities/                  URL normalisation, address policy, Tailscale detection, validators
  ViewModels/                 MVVM: AppState plus one view model per section
  Views/                      SwiftUI screens
  Widget/                     code shared with the widget extension (snapshot, deep links)
AdGuardWidgets/               WidgetKit extension (home and lock screen widgets)
AdGuardControlTests/          unit tests
AdGuardControlUITests/        XCUITest UI tests
branding/final/               logo (SVG) and the 1024 px app icon
docs/                         documentation (English) and docs/pl (Polish)
```

## Tests

Unit tests use `URLProtocol`, so they need no network or server. UI tests start the app with `-uitest`, which swaps the network layer for a built-in stub server (compiled in Debug builds only). Details in [docs/development.md](docs/development.md).

## License

[MIT](LICENSE)
