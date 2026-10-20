# Development

**English** · [Polski](pl/development.md) · [Back to README](../README.md)

## Tooling

- Xcode 16 or newer (developed with Xcode 27), iOS 17+ deployment target, Swift 5 language mode.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` is the source of truth and `AdGuardControl.xcodeproj` is generated (and git-ignored). Run `xcodegen generate` after cloning and after adding or removing source files.
- No third-party packages.

## Targets

| Target | Type | Purpose |
|---|---|---|
| `AdGuardControl` | app | the iOS app |
| `AdGuardWidgets` | app extension | WidgetKit widgets; compiles `Models`, `Networking`, `Storage`, `Utilities` and `Widget` from the app target |
| `AdGuardControlTests` | unit tests | 141 tests, no network |
| `AdGuardControlUITests` | UI tests | 5 XCUITest flows against a built-in stub server |

## Architecture

MVVM with `ObservableObject`:

- `AppState` owns profiles, the active API client, toasts and the selected tab.
- `BaseViewModel` provides ticketed, cancellable loading, `mutate` with undo toasts, and "refresh only if stale" logic. Each screen has one view model.
- `AdGuardAPIClient` uses `URLSession` with async/await, a small TTL cache (invalidated by every non-GET request), per-request redirect refusal and sanitised errors.
- Settings forms use "read, modify, write" against fresh server state and detect conflicts instead of overwriting.
- `AddressPolicy` and `ProfileValidator` guard every address and field (see [security.md](security.md)).

## Running the tests

```bash
xcodebuild -project AdGuardControl.xcodeproj -scheme AdGuardControl \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- **Unit tests** use a `URLProtocol` mock and an in-memory password store, so they need no network, Keychain entitlements or server.
- **UI tests** launch the app with `-uitest` (add `-uitest-empty` for the first-run flow). The app then uses `UITestSupport.swift`, a stateful stub of the AdGuard Home API. That file is wrapped in `#if DEBUG` and is not part of Release builds.

## Running on a real iPhone

The project ships with generic identifiers (`pl.adguardcontrol.*`) that you cannot sign with your own Apple ID. Before running on a device:

1. Choose your own bundle identifiers. In `project.yml` change `bundleIdPrefix` and every `PRODUCT_BUNDLE_IDENTIFIER` (app, widget extension, tests). The widget bundle id must start with the app's bundle id.
2. Choose your own App Group name (for example `group.com.example.adguardcontrol`). Update it in:
   - `AdGuardControl/Storage/SharedStorage.swift` (`appGroup`)
   - `project.yml` (both `entitlements` blocks, `application-groups` and `keychain-access-groups`)
3. Run `xcodegen generate`, open the project and set your **Team** for the `AdGuardControl` and `AdGuardWidgets` targets under *Signing & Capabilities*.
4. Make sure both targets have the **App Groups** and **Keychain Sharing** capabilities with the identifiers from step 2.
5. Build and run on the device. The first launch asks for local network access; allow it.

You can also set `DEVELOPMENT_TEAM` in `project.yml` under `settings.base`, but do not commit your own Team ID if you want the repository to stay generic.

## Adding screenshots

Screenshots in `docs/images` were taken in the iOS Simulator against a local mock server with fake data (no real server addresses or credentials). If you replace them, keep them free of personal data.

## Contributing

Issues and pull requests are welcome. Please keep the project dependency-free, keep passwords out of anything but the Keychain, and add tests for behaviour changes. Run the full test suite before opening a pull request.
