# Widgety

[English](../widgets.md) · **Polski** · [Wróć do README](../../README.pl.md)

<p align="center"><img src="../images/widgets.png" width="40%" alt="Widgety na ekranie głównym"></p>

Widget **AdGuard Home** (WidgetKit, iOS 17+) dodasz z ekranu głównego (przytrzymaj tło → dodaj widżet) albo z ekranu blokady.

| Rozmiar | Zawartość |
|---|---|
| Mały | nazwa serwera, stan ochrony, % zablokowanych, przycisk **Pauza N min** / **Włącz** |
| Średni | to samo + liczba zapytań (24 h), zablokowane i najczęściej blokowana domena |
| Ekran blokady (okrągły, prostokątny, w linii) | wskaźnik % zablokowanych i stan ochrony |

## Zachowanie

- Serwer wybierasz w konfiguracji widgetu („Edytuj widżet”). Bez wyboru widget pokazuje serwer aktywny w aplikacji.
- Czas pauzy (5 min, 10 min, 30 min, 1 godz.) wybierasz w tym samym miejscu.
- Przycisk działa bez otwierania aplikacji (App Intents) i od razu odświeża widget.
- Dotknięcie widgetu otwiera aplikację na Dashboardzie tego serwera, a dotknięcie najczęściej blokowanej domeny (widget średni) otwiera Query Log. Adresy mają postać `adguardcontrol://open?tab=querylog&profile=<UUID>`; poprawne zakładki to `dashboard`, `protection`, `querylog`, `filters`, `more`. Nieznane adresy są ignorowane.
- Dane odświeżają się co ok. 15 minut (po błędzie co 5 minut). Zmiana profilu lub ochrony w aplikacji odświeża je natychmiast. iOS może ograniczać częstotliwość odświeżeń widgetów.
- Błędy (brak sieci, Tailscale wyłączony, błędne hasło) są pokazywane w widgecie zamiast starych danych.

## Jak to działa i co z bezpieczeństwem

- Profile (bez haseł) leżą w **App Group** `group.pl.adguardcontrol.shared`. Hasła zostają **wyłącznie w Keychain**, we wspólnej grupie dostępu `pl.adguardcontrol.shared`. Hasła zapisane przed dodaniem widgetów są przenoszone przy pierwszym uruchomieniu.
- Dostępność hasła to „po pierwszym odblokowaniu, tylko to urządzenie” (`AfterFirstUnlockThisDeviceOnly`), bo widget odświeża się w tle także przy zablokowanym ekranie. Hasło nigdy nie opuszcza urządzenia.
- Widget używa tego samego klienta API i `AddressPolicy` co aplikacja (HTTP tylko do sieci prywatnych / Tailscale, brak przekierowań). Gdy brakuje hasła, nie wysyła żadnych żądań.
- iPhone musi mieć dostęp do serwera (Wi-Fi domowe lub Tailscale) w momencie odświeżenia.

## Uruchomienie na prawdziwym urządzeniu

Oba targety (`AdGuardControl` i `AdGuardWidgets`) potrzebują tego samego Teamu oraz uprawnień **App Groups** i **Keychain Sharing** z powyższymi identyfikatorami (są już w plikach `*.entitlements`). Jeśli zmienisz prefiks bundle identifier, zmień też nazwę grupy w `AdGuardControl/Storage/SharedStorage.swift` i w `project.yml`. Zob. [development.md](development.md#uruchomienie-na-prawdziwym-iphonie).
