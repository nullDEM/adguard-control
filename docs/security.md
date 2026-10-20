# Security

**English** · [Polski](pl/security.md) · [Back to README](../README.md)

## Credentials

- Passwords are stored **only in the iOS Keychain**, never in `UserDefaults`, files or logs. Profiles hold the name, address, login and the "Require Tailscale" flag.
- The app never logs passwords or `Authorization` headers. Error messages shown to the user are sanitised (HTML stripped, length limited) and never contain credentials.
- The login must not contain `:` or control characters (HTTP Basic limitation, RFC 7617).

## Network policy (`AddressPolicy`)

Every server address is checked when a profile is saved and **again on every request**:

| Host class | Examples | Cleartext HTTP |
|---|---|---|
| Tailscale | `100.64.0.0/10`, `*.ts.net`, `fd7a:115c:a1e0::/48` | allowed |
| Private network | RFC 1918, `*.local`, `*.lan`, short names, ULA | allowed (the app warns about it) |
| Loopback | `localhost`, `127.0.0.0/8`, `::1` | allowed |
| Public internet | anything else | **rejected, HTTPS required** |
| Forbidden | `0.0.0.0/8`, broadcast, multicast, link-local (`169.254.0.0/16`, includes cloud metadata), `::` | **rejected** |

Other protections:

- HTTP redirects are **never followed**, so credentials cannot be forwarded to another host.
- TLS validation is never disabled. A certificate error is reported to the user.
- With **Require Tailscale** the app sends nothing until the iPhone has an active Tailscale (`utun`) interface with an address in `100.64.0.0/10`.
- Destructive or sweeping actions (disable protection, change intervals, make a lease static, block a domain from a swipe) ask for confirmation. Settings forms detect that the server changed in the meantime and refuse to overwrite it.
- Widgets apply the same policy and send nothing when the password is missing.

## Why App Transport Security is relaxed

`Info.plist` sets `NSAllowsArbitraryLoads`. ATS cannot express an exception for the Tailscale range (`100.64.0.0/10`): tests showed that HTTP to `100.x.y.z` is blocked even with `NSAllowsLocalNetworking`, and `*.ts.net` exceptions do not cover bare IP addresses. Disabling ATS is compensated by `AddressPolicy` above, which is stricter than ATS for public hosts. Traffic inside a tailnet is encrypted by WireGuard, and HTTP Basic authentication is still required by the server.

If you only use HTTPS servers, you can tighten ATS in `project.yml` by removing `NSAllowsArbitraryLoads`.

## Keychain details

- Items use the service `pl.adguardcontrol.app.credentials` and the profile UUID as the account.
- Accessibility is `AfterFirstUnlockThisDeviceOnly`, so widgets can refresh in the background. The items are not synced to iCloud and not included in backups to other devices.
- Items are shared between the app and the widget extension through the access group `<TeamID>.pl.adguardcontrol.shared`.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's private vulnerability reporting for this repository (Security → Report a vulnerability), or contact the maintainer privately.

## Good practice for your server

- Use a strong, unique password for the AdGuard Home web interface.
- Keep the web interface reachable only from your LAN and your tailnet. Do not forward its port on your router.
- Rotate the password if it was ever pasted into chats, tickets or screenshots.
