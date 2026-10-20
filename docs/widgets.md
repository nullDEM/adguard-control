# Widgets

**English** · [Polski](pl/widgets.md) · [Back to README](../README.md)

<p align="center"><img src="images/widgets.png" width="40%" alt="Home screen widgets"></p>

The **AdGuard Home** widget (WidgetKit, iOS 17+) can be added from the home screen (touch and hold the background → add widget) or from the lock screen.

| Size | Content |
|---|---|
| Small | server name, protection state, % blocked, a **Pause N min** / **Enable** button |
| Medium | the same plus queries (24 h), blocked count and the most-blocked domain |
| Lock screen (circular, rectangular, inline) | % blocked gauge and protection state |

## Behaviour

- Choose the server in the widget configuration ("Edit widget"). Without a choice the widget shows the server that is active in the app.
- Choose the pause length (5 min, 10 min, 30 min, 1 hour) in the same place.
- The button works without opening the app (App Intents) and refreshes the widget right away.
- Tapping the widget opens the app on the Dashboard of that server. Tapping the most-blocked domain (medium widget) opens the Query Log. Links look like `adguardcontrol://open?tab=querylog&profile=<UUID>`; valid tabs are `dashboard`, `protection`, `querylog`, `filters`, `more`. Unknown links are ignored.
- Data refreshes about every 15 minutes (every 5 minutes after an error). Changing the profile or protection in the app refreshes it immediately. iOS may throttle widget refreshes.
- Errors (no network, Tailscale off, wrong password) are shown in the widget instead of stale data.

## How it works and what it means for security

- Profiles (without passwords) live in the **App Group** `group.pl.adguardcontrol.shared`. Passwords stay **only in the Keychain**, in the shared access group `pl.adguardcontrol.shared`. Passwords saved before widgets existed are migrated on first launch.
- Password accessibility is "after first unlock, this device only" (`AfterFirstUnlockThisDeviceOnly`), because widgets refresh in the background even when the screen is locked. The password never leaves the device.
- The widget uses the same API client and `AddressPolicy` as the app (HTTP only to private networks / Tailscale, no redirects). It sends no request when the password is missing.
- The iPhone must be able to reach the server (home Wi-Fi or Tailscale) at the moment of the refresh.

## Running on a real device

Both targets (`AdGuardControl` and `AdGuardWidgets`) need the same signing Team and the **App Groups** and **Keychain Sharing** capabilities with the identifiers above (already present in the `*.entitlements` files). If you change the bundle identifier prefix, rename the group in `AdGuardControl/Storage/SharedStorage.swift` and in `project.yml`. See [development.md](development.md#running-on-a-real-iphone).
