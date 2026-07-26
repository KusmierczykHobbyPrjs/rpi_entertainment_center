# 75-port-forwarding — reach LAN devices through the Pi

The Pi is on Meshnet and reachable from anywhere. The devices around it
usually are not — an old Android phone running an IP webcam cannot run a VPN
client, and putting it on the public internet is exactly what you do not want.

`socat` listens on a port on the Pi and relays to the device, so
`meshnet-address:8282` becomes the webcam without the webcam being exposed to
anyone else.

```bash
./install.sh 75-port-forwarding
```

**Prerequisites:** `00-base`. Only useful alongside `70-nordvpn`.

---

## Configuration

```bash
REC_PORT_FORWARDS=(
    "8282:192.168.1.20:8080"
)
```

Format: `LISTEN_PORT:TARGET_HOST:TARGET_PORT`. Add as many as you like:

```bash
REC_PORT_FORWARDS=(
    "8282:192.168.1.20:8080"    # IP webcam on an old Android phone
    "8283:192.168.1.30:80"      # NAS web interface
    "9100:192.168.1.40:9100"    # network printer
)
```

Pick listening ports above 1024 — anything lower needs root.

---

## The original use case

An old Android phone with [IP Webcam](https://play.google.com/store/apps/details?id=com.pas.webcam)
installed makes a perfectly good home camera. It serves a stream on port 8080
on the LAN, and that is all it can do — no VPN client, no cloud account.

Forwarding `8282` on the Pi to `192.168.1.20:8080` means the camera is
reachable from anywhere through the Pi's Meshnet address, without a
subscription and without the camera ever being publicly exposed.

---

## Using it

The forwards start at boot from `autostart.sh`. Start them now without
rebooting:

```bash
bash bin/port_forwarding.sh &
```

Then:

| From | Address |
|---|---|
| On the LAN | `http://<pi-lan-ip>:8282` |
| From anywhere | `http://<pi-meshnet-address>:8282` |

Find the Meshnet address with `nordvpn meshnet peer list`.

---

## How it works

One `socat` process per forward:

```bash
socat tcp-listen:8282,fork,reuseaddr tcp:192.168.1.20:8080
```

| Option | Why |
|---|---|
| `fork` | Handle more than one client at a time. Without it, a second viewer is refused. |
| `reuseaddr` | Rebind immediately after a restart instead of waiting out the TCP `TIME_WAIT` window. |

The script traps its own exit and kills the children. Without that, `socat`
processes survive, keep holding the ports, and the next start fails silently.

The installer additionally checks each port is free and pings each target, so
a typo in an IP address surfaces immediately rather than as a forward that
quietly does nothing.

---

## Security

**These forwards have no authentication of their own.** Anything that can
reach the port reaches the device.

That is fine over Meshnet, which is private to your NordVPN account.

**Do not forward the same ports on your router** unless the device behind them
has its own password. Doing so publishes the device to the entire internet —
and consumer IP cameras are among the most scanned-for devices there are.

If you want something genuinely public, use module `80-webserver`, which sets
up HTTPS and hardening properly.

---

## Verify

```bash
./bin/doctor.sh net
```

Manually:

```bash
ss -tlnp | grep socat            # is it listening?
curl -I http://localhost:8282    # does the target respond through it?
```

---

## Troubleshooting

**"Address already in use"**

Something else owns that port:

```bash
ss -tlnp "sport = :8282"
```

Either stop it, or pick a different listening port.

A leftover `socat` from a previous run is the usual culprit:

```bash
pkill -f "socat tcp-listen"
```

**The forward is listening but nothing comes back**

Test the target directly from the Pi:

```bash
curl -I http://192.168.1.20:8080
```

If that fails, the problem is the device, not the forward — check it is
powered on, that its IP has not changed (DHCP), and that it is not asleep.
Give it a static DHCP lease in your router.

**It works on the LAN but not over Meshnet**

- Check Meshnet is up on both ends: `nordvpn meshnet peer list`
- Confirm you are using the Pi's **Meshnet** address, not its LAN address.
- Check the firewall: `sudo ufw status`. Re-run
  `./install.sh 75-port-forwarding` to re-open the configured ports.

**It stopped working when the VPN connected**

Your LAN subnet is not allowlisted — the traffic to the target device is being
routed into the tunnel. See [70-nordvpn.md](70-nordvpn.md#ssh-drops-the-moment-the-vpn-connects).

**The forwards are not running after boot**

```bash
pgrep -af port_forwarding.sh
```

They start from `autostart.sh`, which only runs on the physical console. Over
SSH it is normal for this to be absent until you reboot.

**Video through the forward is choppy**

Every byte passes through the Pi, and a Pi 3B's Ethernet shares the USB bus.
Reduce the camera's resolution or bitrate; the Pi is the bottleneck, not the
link.
