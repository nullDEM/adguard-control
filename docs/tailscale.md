# Tailscale, ports and Raspberry Pi setup

**English** · [Polski](pl/tailscale.md) · [Back to README](../README.md)

AdGuard Control talks to the AdGuard Home web API (`/control/...`) with HTTP Basic authentication. Reaching it from outside your home network safely is easiest with [Tailscale](https://tailscale.com). The app never installs or configures Tailscale; it only detects whether a Tailscale interface is active.

**Never expose the AdGuard Home web interface to the public internet** (no router port forwarding for it).

## Where does Tailscale need to be installed?

**On the iPhone: always.** The phone must be in the same tailnet (same Tailscale account) as the rest. On the server side you have three options:

| Scenario | Tailscale on the AdGuard Home machine | Address in the app | When to choose it |
|---|---|---|---|
| **A. On the AdGuard Home machine** (recommended) | yes | `http://100.x.y.z:3000` or a MagicDNS name | simplest and most reliable; independent of other computers |
| **B. On another machine in the same network (subnet router)** | no | plain LAN address, e.g. `http://192.168.1.10:3000` | when you cannot or do not want to install Tailscale on the Raspberry Pi / NAS / router |
| **C. No Tailscale on the server or any LAN machine** | no | n/a | **will not work** away from home: nothing lets the phone into your home network |

"Some computer with Tailscale on the network" is **not enough** by itself. It has to be configured as a *subnet router* (scenario B). Otherwise it is just another device in the tailnet and does not expose the rest of your network.

### Scenario B step by step (subnet router)

Assume a home network `192.168.1.0/24`, AdGuard Home at `192.168.1.10:3000`, and Tailscale on a Linux machine (mini PC, second Raspberry Pi, server).

1. **Install Tailscale** on that machine and sign in with the same account as the iPhone:

   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. **Enable IP forwarding:**

   ```bash
   echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
   sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
   ```

3. **Advertise the route.** Share the whole network, or just one device (safer):

   ```bash
   sudo tailscale up --advertise-routes=192.168.1.0/24     # whole network
   sudo tailscale up --advertise-routes=192.168.1.10/32    # only AdGuard Home
   ```

4. **Approve the route** at <https://login.tailscale.com/admin/machines> → that machine → *Edit route settings*. Also consider *Disable key expiry* so the route does not vanish after a few months.
5. **On the iPhone**, turn Tailscale on (iOS accepts advertised routes automatically).
6. **In AdGuard Control**, add the server with the **LAN address** (`http://192.168.1.10:3000`). Enable *Require Tailscale* if you want to be sure no request leaves the phone without the tunnel.

Limitations of scenario B:

- the Tailscale machine must be **on and online**, otherwise you lose access to AdGuard Home;
- iPhone ↔ machine traffic is encrypted by Tailscale, but the last hop (machine ↔ AdGuard Home on the LAN) is plain HTTP, exactly like at home;
- at home you can connect to the LAN address directly (turn *Require Tailscale* off for that profile); away from home the LAN address only works through the subnet router;
- AdGuard Home must listen on the LAN address (by default it listens on all interfaces).

Test for scenario B (from a device in the tailnet, outside the LAN):

```bash
curl -u LOGIN:PASSWORD http://192.168.1.10:3000/control/status
```

If this returns JSON, the app will connect too. `Connection timed out` usually means the route is not approved, IP forwarding is off, or the Tailscale machine is down.

## Web interface port (80, 3000 or something else)

The port in the address must be **exactly the one AdGuard Home serves its web interface on**. It depends on your installation and is the most common cause of "Connection refused":

| Port | When | How to enter the address |
|---|---|---|
| **80** | typically after the setup wizard is finished | `http://100.x.y.z` with **no port** (80 is the HTTP default) |
| **3000** | the first-run wizard, or if you chose 3000 in it | `http://100.x.y.z:3000` |
| **443 / other** | HTTPS or a custom port set in AdGuard Home | `https://host` or `http://100.x.y.z:PORT` |

How to check the port:

```bash
# on the Raspberry Pi: the http section of the configuration (path depends on the install)
sudo grep -A3 '^http:' /opt/AdGuardHome/AdGuardHome.yaml

# on the Raspberry Pi: what the process is actually listening on
sudo ss -tlnp | grep -i adguard
```

```bash
# from a computer in the tailnet: 401 means "AdGuard is here, login required"
for p in 80 3000 443; do printf "port $p: "; curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://100.x.y.z:$p/control/status; done
```

`401` on a port means it is the right address and only the login is missing. `000` (no response) means nothing listens there. Port 53 is DNS, not the web interface.

## Raspberry Pi (scenario A)

```bash
# 1. Install (Raspberry Pi OS / Debian)
curl -fsSL https://tailscale.com/install.sh | sh

# 2. Start and sign in (prints an authorisation link)
sudo tailscale up

# 3. Start on every boot
sudo systemctl enable --now tailscaled

# 4. The device's Tailscale address
tailscale ip -4

# 5. Devices in the tailnet and their state
tailscale status
```

Recommendations:

- In the admin console choose **⋯ → Disable key expiry** for the Pi so it does not sign out after 180 days.
- Make sure the AdGuard Home web interface listens on all interfaces (`http: address: 0.0.0.0:3000` in `AdGuardHome.yaml`) or on the Tailscale address. Listening only on `127.0.0.1` makes a connection impossible.
- Do **not** open the web interface port on your router. Traffic travels through the encrypted WireGuard tunnel.
- Optionally add the Pi's Tailscale address as a *Global nameserver* under *Tailscale admin → DNS* so every device in the tailnet uses AdGuard Home.

## iPhone

1. Install **Tailscale** from the App Store.
2. Sign in with the **same account** (tailnet) as the Pi.
3. Turn the VPN switch on (a VPN icon appears in the iOS status bar).
4. In AdGuard Control use `http://100.x.y.z:3000` or the MagicDNS name `http://adguard-home.your-tailnet.ts.net:3000` (the tailnet name is in the admin console under DNS). The short name `http://adguard-home:3000` works when MagicDNS is on.

## Finding the Pi's address

- On the Pi: `tailscale ip -4`, for example `100.101.102.103`
- On the Pi: `tailscale status` lists devices and addresses
- In the admin console: <https://login.tailscale.com/admin/machines>, column *Addresses*

## Testing the connection

From a computer in the same tailnet:

```bash
tailscale ping 100.x.y.z
curl -u LOGIN:PASSWORD http://100.x.y.z:3000/control/status
```

A good answer is JSON such as `{"protection_enabled":true,"running":true,"version":"v0.107.x",...}`.

| `curl` result | Meaning |
|---|---|
| JSON status | everything works, use the same credentials in the app |
| `401 Unauthorized` | wrong login or password |
| `Connection refused` | AdGuard Home is not listening on that port/interface |
| `Connection timed out` | Tailscale is off, the Pi is offline, or the address is wrong |

When a connection fails, the app shows a checklist: is the iPhone connected to Tailscale, is the Pi online in the admin console, is AdGuard Home listening on the given port, are the address and port correct. The app also works with Tailscale off (for example on your LAN) and shows a readable error if the server is unreachable.
