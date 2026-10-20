# Rozwój

[English](../development.md) · **Polski** · [Wróć do README](../../README.pl.md)

## Narzędzia

- Xcode 16 lub nowszy (rozwijane w Xcode 27), iOS 17+, tryb językowy Swift 5.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` jest źródłem prawdy, a `AdGuardControl.xcodeproj` jest generowany (i ignorowany przez git). Uruchom `xcodegen generate` po sklonowaniu repozytorium oraz po dodaniu lub usunięciu plików źródłowych.
- Brak pakietów zewnętrznych.

## Targety

| Target | Typ | Cel |
|---|---|---|
| `AdGuardControl` | aplikacja | aplikacja iOS |
| `AdGuardWidgets` | rozszerzenie | widgety WidgetKit; kompiluje `Models`, `Networking`, `Storage`, `Utilities` i `Widget` z targetu aplikacji |
| `AdGuardControlTests` | testy jednostkowe | 141 testów, bez sieci |
| `AdGuardControlUITests` | testy UI | 5 scenariuszy XCUITest z wbudowanym serwerem testowym |

## Architektura

MVVM z `ObservableObject`:

- `AppState` przechowuje profile, aktywnego klienta API, komunikaty i wybraną zakładkę.
- `BaseViewModel` zapewnia ładowanie z numerami wywołań i anulowaniem, `mutate` z komunikatami „Cofnij” oraz odświeżanie tylko nieaktualnych danych. Każdy ekran ma jeden view model.
- `AdGuardAPIClient` używa `URLSession` z async/await, małej pamięci podręcznej z TTL (czyszczonej przy każdym żądaniu innym niż GET), odmowy przekierowań i oczyszczonych błędów.
- Formularze ustawień używają wzorca „odczyt, zmiana, zapis” na świeżym stanie serwera i wykrywają konflikty zamiast nadpisywać.
- `AddressPolicy` i `ProfileValidator` pilnują każdego adresu i pola (zob. [security.md](security.md)).

## Uruchamianie testów

```bash
xcodebuild -project AdGuardControl.xcodeproj -scheme AdGuardControl \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- **Testy jednostkowe** używają atrapy `URLProtocol` i magazynu haseł w pamięci, więc nie potrzebują sieci, uprawnień Keychain ani serwera.
- **Testy UI** uruchamiają aplikację z `-uitest` (dodaj `-uitest-empty` dla pierwszego uruchomienia). Aplikacja używa wtedy `UITestSupport.swift`, stanowej atrapy API AdGuard Home. Plik jest objęty `#if DEBUG` i nie wchodzi do buildów Release.

## Uruchomienie na prawdziwym iPhonie

Projekt zawiera ogólne identyfikatory (`pl.adguardcontrol.*`), których nie podpiszesz własnym Apple ID. Przed uruchomieniem na urządzeniu:

1. Wybierz własne bundle identifiers. W `project.yml` zmień `bundleIdPrefix` i każdy `PRODUCT_BUNDLE_IDENTIFIER` (aplikacja, rozszerzenie widgetu, testy). Identyfikator widgetu musi zaczynać się od identyfikatora aplikacji.
2. Wybierz własną nazwę App Group (np. `group.com.example.adguardcontrol`). Zmień ją w:
   - `AdGuardControl/Storage/SharedStorage.swift` (`appGroup`)
   - `project.yml` (oba bloki `entitlements`, `application-groups` i `keychain-access-groups`)
3. Uruchom `xcodegen generate`, otwórz projekt i ustaw swój **Team** dla targetów `AdGuardControl` i `AdGuardWidgets` w *Signing & Capabilities*.
4. Upewnij się, że oba targety mają uprawnienia **App Groups** i **Keychain Sharing** z identyfikatorami z kroku 2.
5. Zbuduj i uruchom na urządzeniu. Przy pierwszym uruchomieniu iOS poprosi o dostęp do sieci lokalnej; zezwól.

Możesz też ustawić `DEVELOPMENT_TEAM` w `project.yml` w `settings.base`, ale nie commituj własnego Team ID, jeśli repozytorium ma pozostać ogólne.

## Zrzuty ekranu

Zrzuty w `docs/images` zostały zrobione w symulatorze iOS z lokalnym serwerem testowym i fikcyjnymi danymi (bez prawdziwych adresów serwerów i poświadczeń). Jeśli je wymieniasz, nie umieszczaj na nich danych osobistych.

## Współtworzenie

Zgłoszenia i pull requesty są mile widziane. Prosimy o zachowanie projektu bez zależności, trzymanie haseł wyłącznie w Keychain oraz dodawanie testów do zmian zachowania. Przed pull requestem uruchom pełny zestaw testów.
