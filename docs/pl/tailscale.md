# Tailscale, porty i konfiguracja Raspberry Pi

[English](../tailscale.md) · **Polski** · [Wróć do README](../../README.pl.md)

AdGuard Control komunikuje się z API webowym AdGuard Home (`/control/...`) przez HTTP Basic. Najłatwiejszy i bezpieczny dostęp spoza sieci domowej zapewnia [Tailscale](https://tailscale.com). Aplikacja nie instaluje ani nie konfiguruje Tailscale, tylko wykrywa, czy interfejs Tailscale jest aktywny.

**Nigdy nie wystawiaj interfejsu webowego AdGuard Home publicznie do internetu** (żadnego przekierowania portów na routerze).

## Gdzie musi być zainstalowany Tailscale?

**Na iPhonie: zawsze.** Telefon musi być w tym samym tailnecie (na tym samym koncie Tailscale) co reszta. Po stronie serwera masz do wyboru trzy scenariusze:

| Scenariusz | Tailscale na urządzeniu z AdGuard Home | Adres w aplikacji | Kiedy wybrać |
|---|---|---|---|
| **A. Na urządzeniu z AdGuard Home** (zalecane) | tak | `http://100.x.y.z:3000` lub nazwa MagicDNS | najprostsze i najpewniejsze; działa niezależnie od innych komputerów |
| **B. Na innym komputerze w tej samej sieci (subnet router)** | nie | zwykły adres LAN, np. `http://192.168.1.10:3000` | gdy nie możesz lub nie chcesz instalować Tailscale na Raspberry Pi / NAS / routerze |
| **C. Brak Tailscale na serwerze i na żadnym urządzeniu w sieci** | nie | – | **nie zadziała** spoza domu: nic nie wpuści telefonu do sieci domowej |

Samo „jakiś komputer z Tailscale w sieci” **nie wystarczy**. Taki komputer musi być skonfigurowany jako *subnet router* (scenariusz B), inaczej jest tylko kolejnym urządzeniem w tailnecie i nie udostępnia reszty sieci.

### Scenariusz B krok po kroku (subnet router)

Załóżmy: sieć domowa `192.168.1.0/24`, AdGuard Home pod `192.168.1.10:3000`, a Tailscale działa na komputerze z Linuksem (mini-PC, drugie Raspberry Pi, serwer).

1. **Zainstaluj Tailscale na tym komputerze** i zaloguj się na to samo konto co iPhone:

   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. **Włącz przekazywanie pakietów (IP forwarding):**

   ```bash
   echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
   sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
   ```

3. **Ogłoś trasę.** Możesz udostępnić całą sieć albo tylko jedno urządzenie (bezpieczniej):

   ```bash
   sudo tailscale up --advertise-routes=192.168.1.0/24     # cała sieć
   sudo tailscale up --advertise-routes=192.168.1.10/32    # tylko AdGuard Home
   ```

4. **Zatwierdź trasę w panelu:** <https://login.tailscale.com/admin/machines> → ten komputer → *Edit route settings*. Warto też wyłączyć wygasanie klucza (*Disable key expiry*), żeby trasa nie zniknęła po kilku miesiącach.
5. **Na iPhonie** włącz Tailscale (iOS przyjmuje ogłoszone trasy automatycznie).
6. **W AdGuard Control** dodaj serwer z **adresem LAN** (`http://192.168.1.10:3000`). Włącz *Wymagaj Tailscale*, jeśli chcesz mieć pewność, że żadne zapytanie nie wyjdzie z telefonu bez tunelu.

Ograniczenia scenariusza B:

- komputer z Tailscale musi być **włączony i online**, inaczej tracisz dostęp do AdGuard Home;
- ruch iPhone ↔ komputer jest szyfrowany przez Tailscale, ale ostatni odcinek (komputer ↔ AdGuard Home w LAN) to zwykłe HTTP, tak samo jak w domu;
- w domu możesz łączyć się bezpośrednio z adresem LAN (wyłącz wtedy *Wymagaj Tailscale* w tym profilu); poza domem adres LAN działa tylko przez subnet router;
- AdGuard Home musi nasłuchiwać na adresie LAN (domyślnie nasłuchuje na wszystkich interfejsach).

Test dla scenariusza B (z urządzenia w tailnecie, poza LAN):

```bash
curl -u LOGIN:HASLO http://192.168.1.10:3000/control/status
```

Jeśli zwraca JSON, aplikacja też się połączy. `Connection timed out` oznacza zwykle niezatwierdzoną trasę, wyłączone IP forwarding albo wyłączony komputer z Tailscale.

## Port interfejsu webowego (80, 3000 czy inny?)

Port w adresie musi być **dokładnie taki, na jakim AdGuard Home udostępnia panel**. To zależy od instalacji i jest najczęstszą przyczyną błędu „Connection refused”:

| Port | Kiedy | Jak wpisać adres |
|---|---|---|
| **80** | typowo po zakończeniu kreatora konfiguracji | `http://100.x.y.z` **bez portu** (80 to domyślny port HTTP) |
| **3000** | kreator pierwszej konfiguracji albo gdy wybrałeś 3000 w kreatorze | `http://100.x.y.z:3000` |
| **443 / inny** | HTTPS lub własny port ustawiony w AdGuard Home | `https://host` lub `http://100.x.y.z:PORT` |

Jak sprawdzić port:

```bash
# na Raspberry Pi: sekcja http w konfiguracji (ścieżka zależy od instalacji)
sudo grep -A3 '^http:' /opt/AdGuardHome/AdGuardHome.yaml

# na Raspberry Pi: na czym faktycznie słucha proces
sudo ss -tlnp | grep -i adguard
```

```bash
# z komputera w tailnecie: 401 oznacza „tu jest AdGuard, wymaga logowania”
for p in 80 3000 443; do printf "port $p: "; curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://100.x.y.z:$p/control/status; done
```

Kod `401` na danym porcie oznacza, że to właściwy adres i brakuje tylko loginu. `000` (brak odpowiedzi) oznacza, że nic tam nie słucha. Port 53 to DNS, nie panel.

## Raspberry Pi (scenariusz A)

```bash
# 1. Instalacja (Raspberry Pi OS / Debian)
curl -fsSL https://tailscale.com/install.sh | sh

# 2. Uruchomienie i logowanie (wyświetli link do autoryzacji)
sudo tailscale up

# 3. Usługa startuje przy każdym uruchomieniu systemu
sudo systemctl enable --now tailscaled

# 4. Adres Tailscale tego urządzenia
tailscale ip -4

# 5. Urządzenia w tailnecie i ich stan
tailscale status
```

Zalecenia:

- W panelu administracyjnym przy Raspberry Pi wybierz **⋯ → Disable key expiry**, żeby urządzenie nie wylogowało się po 180 dniach.
- Upewnij się, że interfejs webowy AdGuard Home nasłuchuje na wszystkich interfejsach (`http: address: 0.0.0.0:3000` w `AdGuardHome.yaml`) albo na adresie Tailscale. Nasłuch tylko na `127.0.0.1` uniemożliwi połączenie.
- **Nie** otwieraj portu interfejsu webowego na routerze. Ruch idzie zaszyfrowanym tunelem WireGuard.
- Opcjonalnie dodaj adres Tailscale Raspberry Pi jako *Global nameserver* w *Tailscale admin → DNS*, żeby wszystkie urządzenia w tailnecie korzystały z AdGuard Home.

## iPhone

1. Zainstaluj aplikację **Tailscale** z App Store.
2. Zaloguj się na **to samo konto** (tailnet), co Raspberry Pi.
3. Włącz przełącznik VPN (w pasku stanu iOS pojawi się ikona VPN).
4. W AdGuard Control użyj adresu `http://100.x.y.z:3000` albo nazwy MagicDNS `http://adguard-home.nazwa-tailnetu.ts.net:3000` (nazwę tailnetu znajdziesz w panelu, w zakładce DNS). Krótka nazwa `http://adguard-home:3000` działa, gdy MagicDNS jest włączony.

## Jak znaleźć adres Raspberry Pi

- Na Raspberry Pi: `tailscale ip -4`, np. `100.101.102.103`
- Na Raspberry Pi: `tailscale status` pokazuje urządzenia i adresy
- W panelu: <https://login.tailscale.com/admin/machines>, kolumna *Addresses*

## Testowanie połączenia

Z komputera w tym samym tailnecie:

```bash
tailscale ping 100.x.y.z
curl -u LOGIN:HASLO http://100.x.y.z:3000/control/status
```

Poprawna odpowiedź to JSON, np. `{"protection_enabled":true,"running":true,"version":"v0.107.x",...}`.

| Wynik `curl` | Znaczenie |
|---|---|
| JSON ze statusem | wszystko działa, użyj tych samych danych w aplikacji |
| `401 Unauthorized` | zły login lub hasło |
| `Connection refused` | AdGuard Home nie nasłuchuje na tym porcie/interfejsie |
| `Connection timed out` | Tailscale wyłączony, Pi offline lub zły adres |

Gdy połączenie w aplikacji zawiedzie, wyświetla ona listę kontrolną: czy iPhone jest połączony z Tailscale, czy Raspberry Pi jest online w panelu, czy AdGuard Home nasłuchuje na podanym porcie, czy adres i port są poprawne. Aplikacja działa także przy wyłączonym Tailscale (np. w LAN), a gdy serwer jest nieosiągalny, pokazuje czytelny błąd.
