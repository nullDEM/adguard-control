# API coverage and known limits

**English** · [Polski](pl/api-coverage.md) · [Back to README](../README.md)

The client follows the official AdGuard Home OpenAPI specification (`openapi/openapi.yaml`, API v0.107). Every endpoint below exists in that specification and none of them is marked deprecated.

## Endpoints used (`/control/...`)

| Area | Endpoints |
|---|---|
| Status / protection | `GET /status`, `POST /protection`, `GET /profile`, `PUT /profile/update`, `POST /version.json`, `POST /update` |
| Statistics | `GET /stats` (`recent`), `POST /stats_reset`, `GET /stats/config`, `PUT /stats/config/update` |
| Query log | `GET /querylog` (`older_than`, `limit`, `search`, `reason`), `POST /querylog_clear`, `GET /querylog/config`, `PUT /querylog/config/update` |
| Filtering | `GET /filtering/status`, `POST /filtering/config`, `POST /filtering/add_url`, `POST /filtering/remove_url`, `POST /filtering/set_url`, `POST /filtering/refresh`, `POST /filtering/set_rules`, `GET /filtering/check_host` |
| Safe browsing / parental / safe search | `GET /safebrowsing/status`, `POST /safebrowsing/enable`, `POST /safebrowsing/disable`, `GET /parental/status`, `POST /parental/enable`, `POST /parental/disable`, `GET /safesearch/status`, `PUT /safesearch/settings` |
| Blocked services | `GET /blocked_services/all`, `GET /blocked_services/get`, `PUT /blocked_services/update` |
| DNS rewrites | `GET /rewrite/list`, `POST /rewrite/add`, `POST /rewrite/delete`, `PUT /rewrite/update`, `GET /rewrite/settings`, `PUT /rewrite/settings/update` |
| Clients | `GET /clients`, `POST /clients/add`, `POST /clients/update`, `POST /clients/delete`, `POST /clients/search` |
| Access control | `GET /access/list`, `POST /access/set` |
| DNS | `GET /dns_info`, `POST /dns_config`, `POST /test_upstream_dns`, `POST /cache_clear` |
| DHCP | `GET /dhcp/status`, `GET /dhcp/interfaces`, `POST /dhcp/set_config`, `POST /dhcp/find_active_dhcp`, `POST /dhcp/add_static_lease`, `POST /dhcp/update_static_lease`, `POST /dhcp/remove_static_lease`, `POST /dhcp/reset`, `POST /dhcp/reset_leases` |
| TLS | `GET /tls/status`, `POST /tls/validate`, `POST /tls/configure` |

Intentionally skipped: endpoints marked *deprecated* in the specification, the install wizard (`/install/*`), cookie sessions (`/login`, `/logout`; the app uses HTTP Basic) and Apple profiles (`/apple/*.mobileconfig`).

## Web UI features covered

- **Overview**: protection status, counters, activity chart, top domains / blocked / clients, recent queries, pausing protection, pull to refresh, statistics range.
- **Protection**: DNS protection, filtering, safe browsing, parental control (on/off), safe search per engine, blocked services, host checker.
- **Query log**: paging (`older_than`), search, status filter (blocked, safe browsing, parental, allowed, rewritten, safe search, processed), client filter, details, quick actions (block domain, allow, custom rule), also by swipe.
- **Filters**: blocklists and allowlists (add, edit, remove, enable, refresh, update interval, rule counts and update time), custom rules (add, edit, remove, disable via `!` comment, text editing), DNS rewrites.
- **Clients**: persistent and runtime clients, add / edit / remove, tags, filtering settings, safe search, blocked services, dedicated upstream DNS, privacy (query log / statistics), block and unblock, query counts and recent queries per client.
- **DNS**: upstreams, bootstrap, fallback, upstream test, query mode (load balance / parallel / fastest), timeout, DNSSEC, IPv6, cache (size, TTL, optimistic), blocking mode, private reverse DNS, EDNS Client Subnet, rate limit, clearing the cache.
- **DHCP**: status, enable, interface, IPv4 range, lease time, active leases (convertible to static), static leases (CRUD), detecting other DHCP servers, reset.
- **Settings**: server profiles, Tailscale preset, general settings (server version, updates, panel language and theme, statistics, query log, clearing statistics/log/cache), TLS/HTTPS (certificate status, validity and chain warnings, validation, configuration), access control (allowed/blocked clients, blocked hosts), the app follows the system appearance (light / dark).

Every configuration change asks for confirmation and shows a result message, with an **Undo** button for most operations. Loading, empty, error and no-permission (401/403) states are handled.

## Unavailable or limited features (and why)

| Feature | Reason |
|---|---|
| Restarting the AdGuard Home service | no endpoint in the OpenAPI spec; use `sudo systemctl restart AdGuardHome` over SSH (the app only offers `POST /update`, i.e. updating) |
| Changing the host name or web interface port | the API does not expose it after installation (the install wizard sets the port, the rest lives in `AdGuardHome.yaml`) |
| DNS rebinding protection | no field in `DNSConfig` (v0.107), configuration file only |
| Parental control sensitivity | `/parental/status` is read-only; only on/off is available |
| "Allowed domains" as a separate list | `AccessList` has only allowed/blocked clients and blocked hosts; domain exceptions are made with an `@@\|\|domain^` rule (Filters → Rules, or the Query Log) |
| Time range filter in the Query Log | `/querylog` has no time range parameter; the app filters the loaded entries locally |
| Blocked-services schedule editor | the `Schedule` model is supported (preserved on save) but there is no time-range editor yet |
| Custom certificates / trusting self-signed | deliberately skipped: certificate errors are reported and TLS validation is never disabled (use HTTP inside a tailnet, or a valid certificate) |
| First-run wizard, cookie login, `.mobileconfig` profiles | out of scope for an app that manages an already configured server |

The UI of the app is currently Polish only.
