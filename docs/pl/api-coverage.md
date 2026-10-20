# Pokrycie API i znane ograniczenia

[English](../api-coverage.md) · **Polski** · [Wróć do README](../../README.pl.md)

Klient jest zgodny z oficjalną specyfikacją OpenAPI AdGuard Home (`openapi/openapi.yaml`, API v0.107). Każdy poniższy endpoint istnieje w tej specyfikacji i żaden nie jest oznaczony jako przestarzały.

## Użyte endpointy (`/control/...`)

| Obszar | Endpointy |
|---|---|
| Status / ochrona | `GET /status`, `POST /protection`, `GET /profile`, `PUT /profile/update`, `POST /version.json`, `POST /update` |
| Statystyki | `GET /stats` (`recent`), `POST /stats_reset`, `GET /stats/config`, `PUT /stats/config/update` |
| Query log | `GET /querylog` (`older_than`, `limit`, `search`, `reason`), `POST /querylog_clear`, `GET /querylog/config`, `PUT /querylog/config/update` |
| Filtrowanie | `GET /filtering/status`, `POST /filtering/config`, `POST /filtering/add_url`, `POST /filtering/remove_url`, `POST /filtering/set_url`, `POST /filtering/refresh`, `POST /filtering/set_rules`, `GET /filtering/check_host` |
| Safe browsing / rodzicielska / safe search | `GET /safebrowsing/status`, `POST /safebrowsing/enable`, `POST /safebrowsing/disable`, `GET /parental/status`, `POST /parental/enable`, `POST /parental/disable`, `GET /safesearch/status`, `PUT /safesearch/settings` |
| Blokowane usługi | `GET /blocked_services/all`, `GET /blocked_services/get`, `PUT /blocked_services/update` |
| DNS rewrites | `GET /rewrite/list`, `POST /rewrite/add`, `POST /rewrite/delete`, `PUT /rewrite/update`, `GET /rewrite/settings`, `PUT /rewrite/settings/update` |
| Klienci | `GET /clients`, `POST /clients/add`, `POST /clients/update`, `POST /clients/delete`, `POST /clients/search` |
| Kontrola dostępu | `GET /access/list`, `POST /access/set` |
| DNS | `GET /dns_info`, `POST /dns_config`, `POST /test_upstream_dns`, `POST /cache_clear` |
| DHCP | `GET /dhcp/status`, `GET /dhcp/interfaces`, `POST /dhcp/set_config`, `POST /dhcp/find_active_dhcp`, `POST /dhcp/add_static_lease`, `POST /dhcp/update_static_lease`, `POST /dhcp/remove_static_lease`, `POST /dhcp/reset`, `POST /dhcp/reset_leases` |
| TLS | `GET /tls/status`, `POST /tls/validate`, `POST /tls/configure` |

Pominięte celowo: endpointy oznaczone w specyfikacji jako *deprecated*, kreator instalacji (`/install/*`), sesja cookie (`/login`, `/logout`; aplikacja używa HTTP Basic) oraz profile Apple (`/apple/*.mobileconfig`).

## Funkcje web UI pokryte przez aplikację

- **Dashboard**: status ochrony, liczniki, wykres aktywności, top domeny / zablokowane / klienci, ostatnie zapytania, pauza ochrony, pull-to-refresh, zakres statystyk.
- **Ochrona**: ochrona DNS, filtrowanie, bezpieczne przeglądanie, kontrola rodzicielska (włącz/wyłącz), bezpieczne wyszukiwanie osobno dla każdej wyszukiwarki, blokowane usługi, sprawdzanie domeny.
- **Query Log**: doczytywanie (`older_than`), wyszukiwanie, filtr statusu (zablokowane, bezp. przeglądanie, rodzicielska, biała lista, przepisane, safe search, przetworzone), filtr klienta, szczegóły, szybkie akcje (blokuj domenę, zezwól, własna reguła), także gestem przesunięcia.
- **Filtry**: listy blokujące i zezwalające (dodawanie, edycja, usuwanie, włączanie, odświeżanie, interwał aktualizacji, liczba reguł i czas aktualizacji), własne reguły (dodawanie, edycja, usuwanie, wyłączanie przez komentarz `!`, edycja tekstowa), DNS rewrites.
- **Klienci**: trwali i tymczasowi, dodawanie / edycja / usuwanie, tagi, ustawienia filtrowania, safe search, blokowane usługi, dedykowane upstream DNS, prywatność (query log / statystyki), blokowanie i odblokowywanie, liczba zapytań i ostatnie zapytania klienta.
- **DNS**: upstream, bootstrap, fallback, test upstreamów, tryb zapytań (load balance / równoległe / najszybszy), timeout, DNSSEC, IPv6, cache (rozmiar, TTL, optymistyczny), tryb blokowania, prywatny reverse DNS, EDNS Client Subnet, rate limit, czyszczenie cache.
- **DHCP**: status, włączanie, interfejs, zakres IPv4, czas dzierżawy, aktywne dzierżawy (z możliwością zamiany na statyczną), statyczne przypisania (CRUD), wykrywanie innych serwerów DHCP, reset.
- **Ustawienia**: profile serwerów, preset Tailscale, ustawienia ogólne (wersja serwera, aktualizacje, język i motyw panelu, statystyki, query log, czyszczenie statystyk/logu/cache), TLS/HTTPS (status certyfikatu, ostrzeżenia o ważności i łańcuchu, walidacja, konfiguracja), kontrola dostępu (dozwolone/zablokowane klienty, blokowane hosty), motyw aplikacji (domyślnie ciemny / jasny / systemowy).

Każda zmiana konfiguracji wymaga potwierdzenia i pokazuje komunikat o wyniku, a większość operacji ma przycisk **Cofnij**. Obsługiwane są stany ładowania, pustych list, błędów i braku uprawnień (401/403).

## Funkcje niedostępne lub ograniczone (i dlaczego)

| Funkcja | Powód |
|---|---|
| Restart usługi AdGuard Home | brak endpointu w OpenAPI; użyj `sudo systemctl restart AdGuardHome` przez SSH (aplikacja oferuje tylko `POST /update`, czyli aktualizację) |
| Zmiana nazwy hosta i portu interfejsu web | po instalacji API tego nie udostępnia (port ustawia kreator instalacji, reszta to `AdGuardHome.yaml`) |
| Ochrona DNS rebinding | brak pola w `DNSConfig` (v0.107), tylko plik konfiguracyjny |
| Zmiana czułości kontroli rodzicielskiej | `/parental/status` jest tylko do odczytu; dostępne tylko włącz/wyłącz |
| „Dozwolone domeny” jako osobna lista | `AccessList` ma tylko dozwolone/zablokowane klienty i blokowane hosty; wyjątki dla domen robi się regułą `@@\|\|domena^` (Filtry → Reguły lub Query Log) |
| Filtr czasu w Query Log | `/querylog` nie ma parametru zakresu czasu; aplikacja filtruje lokalnie załadowane wpisy |
| Edytor harmonogramu blokowania usług | model `Schedule` jest obsługiwany (zachowywany przy zapisie), ale nie ma jeszcze edytora przedziałów godzin |
| Własne certyfikaty / zaufanie do self-signed | świadomie pominięte: błędy certyfikatu są zgłaszane, a weryfikacja TLS nigdy nie jest wyłączana (w tailnecie używaj HTTP lub poprawnego certyfikatu) |
| Kreator pierwszej instalacji, logowanie cookie, profile `.mobileconfig` | poza zakresem aplikacji zarządzającej już skonfigurowanym serwerem |

Interfejs aplikacji jest obecnie wyłącznie po polsku.
