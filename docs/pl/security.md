# Bezpieczeństwo

[English](../security.md) · **Polski** · [Wróć do README](../../README.pl.md)

## Poświadczenia

- Hasła są przechowywane **wyłącznie w Keychain iOS**, nigdy w `UserDefaults`, plikach ani logach. Profile zawierają nazwę, adres, login i flagę „Wymagaj Tailscale”.
- Aplikacja nigdy nie loguje haseł ani nagłówków `Authorization`. Komunikaty błędów pokazywane użytkownikowi są oczyszczane (usuwany HTML, ograniczona długość) i nie zawierają poświadczeń.
- Login nie może zawierać `:` ani znaków sterujących (ograniczenie HTTP Basic, RFC 7617).

## Polityka sieciowa (`AddressPolicy`)

Każdy adres serwera jest sprawdzany przy zapisie profilu i **ponownie przy każdym żądaniu**:

| Klasa hosta | Przykłady | HTTP bez szyfrowania |
|---|---|---|
| Tailscale | `100.64.0.0/10`, `*.ts.net`, `fd7a:115c:a1e0::/48` | dozwolone |
| Sieć prywatna | RFC 1918, `*.local`, `*.lan`, krótkie nazwy, ULA | dozwolone (aplikacja ostrzega) |
| Loopback | `localhost`, `127.0.0.0/8`, `::1` | dozwolone |
| Internet publiczny | cała reszta | **odrzucone, wymagany HTTPS** |
| Zakazane | `0.0.0.0/8`, broadcast, multicast, link-local (`169.254.0.0/16`, w tym metadane chmury), `::` | **odrzucone** |

Pozostałe zabezpieczenia:

- Przekierowania HTTP **nigdy nie są śledzone**, więc poświadczenia nie mogą trafić na inny host.
- Weryfikacja TLS nigdy nie jest wyłączana. Błąd certyfikatu jest zgłaszany użytkownikowi.
- Przy opcji **Wymagaj Tailscale** aplikacja nie wysyła nic, dopóki iPhone nie ma aktywnego interfejsu Tailscale (`utun`) z adresem w `100.64.0.0/10`.
- Akcje zmieniające lub masowe (wyłączenie ochrony, zmiana interwałów, zamiana dzierżawy na statyczną, blokowanie domeny gestem przesunięcia) wymagają potwierdzenia. Formularze ustawień wykrywają, że serwer zmienił się w międzyczasie, i odmawiają nadpisania.
- Widgety stosują tę samą politykę i nie wysyłają niczego, gdy brakuje hasła.

## Dlaczego App Transport Security jest złagodzony

`Info.plist` ustawia `NSAllowsArbitraryLoads`. ATS nie potrafi wyrazić wyjątku dla zakresu Tailscale (`100.64.0.0/10`): testy pokazały, że HTTP do `100.x.y.z` jest blokowane nawet z `NSAllowsLocalNetworking`, a wyjątki `*.ts.net` nie obejmują adresów IP. Wyłączenie ATS kompensuje powyższa `AddressPolicy`, która dla hostów publicznych jest ostrzejsza niż ATS. Ruch w tailnecie jest szyfrowany przez WireGuard, a serwer nadal wymaga uwierzytelnienia HTTP Basic.

Jeśli używasz wyłącznie serwerów z HTTPS, możesz zaostrzyć ATS w `project.yml`, usuwając `NSAllowsArbitraryLoads`.

## Szczegóły Keychain

- Elementy używają usługi `pl.adguardcontrol.app.credentials`, a kontem jest UUID profilu.
- Dostępność to `AfterFirstUnlockThisDeviceOnly`, żeby widgety mogły się odświeżać w tle. Elementy nie są synchronizowane z iCloud ani przenoszone w kopiach zapasowych na inne urządzenia.
- Elementy są współdzielone między aplikacją a rozszerzeniem widgetu przez grupę dostępu `<TeamID>.pl.adguardcontrol.shared`.

## Zgłaszanie podatności

Nie zakładaj publicznego zgłoszenia (issue) dla problemów bezpieczeństwa. Użyj prywatnego zgłaszania podatności na GitHubie dla tego repozytorium (Security → Report a vulnerability) albo skontaktuj się z autorem prywatnie.

## Dobre praktyki dla serwera

- Używaj silnego, unikalnego hasła do interfejsu webowego AdGuard Home.
- Udostępniaj interfejs webowy tylko w sieci LAN i tailnecie. Nie przekierowuj jego portu na routerze.
- Zmień hasło, jeśli kiedykolwiek trafiło do czatów, zgłoszeń lub zrzutów ekranu.
