# 70-nordvpn — VPN and Meshnet

Two distinct things from one client, and it is worth being clear about which
is which:

- **VPN** — outbound traffic leaves through another country. Used to reach
  region-locked catch-up TV.
- **Meshnet** — a private network between your own devices. This is what makes
  the Pi reachable from anywhere **without opening a single port on your
  router**.

```bash
./install.sh 70-nordvpn
```

**Prerequisites:** `00-base`, a NordVPN subscription. Install `90-speech`
first if you want spoken status announcements.

---

## What it does

1. Runs NordVPN's official installer (it is not in the Debian archive).
2. Adds you to the `nordvpn` group, so VPN commands work without `sudo` — the
   button scripts and Kodi menu cannot supply a password.
3. Enables the `nordvpnd` daemon.
4. Logs in with `NORDVPN_TOKEN` from `config.sh`.
5. **Allowlists your LAN subnet.**
6. Enables Meshnet.

---

## Configuration

```bash
export NORDVPN_COUNTRIES="xx pl fi uk"
export NORDVPN_LAN_SUBNET="192.168.1.0/24"
export NORDVPN_MESHNET="on"
export NORDVPN_TOKEN=""
```

### `NORDVPN_LAN_SUBNET` — get this right

**Connecting the VPN routes all traffic into the tunnel, including traffic to
your own network.** Without this allowlist entry, SSH drops, the Kore remote
stops working and every port forward dies the moment the VPN connects.

Find yours:

```bash
ip route | grep -v default | grep "$(hostname -I | awk '{print $1}' | cut -d. -f1-3)"
```

Usually `192.168.1.0/24` or `192.168.0.0/24`.

`doctor.sh` cross-checks this against the Pi's actual address and fails loudly
if they disagree — this is the single most common way to lock yourself out.

### `NORDVPN_TOKEN`

Generate at <https://my.nordaccount.com/dashboard/nordvpn/> → **Access token**.

Needed for automatic login at boot. Leave it empty and run `nordvpn login`
manually instead; the VPN still works, it just will not log itself back in
after the token expires.

This is why `config.sh` is git-ignored and mode 600.

### `NORDVPN_COUNTRIES`

The list the VPN button cycles through, wrapping at the end:

- Country codes: `pl`, `fi`, `uk`, `us`, `de`
- A specific server: `uk2431`
- **`xx` means disconnected** — include it for a no-VPN position

`"xx pl fi uk"` gives: no VPN → Poland → Finland → UK → no VPN → …

If the **first** entry is `xx`, the VPN does not connect at boot.

---

## Using it

| Action | How |
|---|---|
| Next country | GPIO 17, or Kodi menu → "VPN next country" |
| Connect to a country | Kodi menu → "VPN Poland", or `bash bin/nordvpn_connect.sh pl` |
| Disconnect | Kodi menu → "VPN disconnect", or `bash bin/nordvpn_disconnect.sh` |
| Hear the status | Kodi menu → "VPN status", or `bash bin/nordvpn_status.sh` |

### The scripts

| Script | Purpose |
|---|---|
| `nordvpn_autostart.sh` | Runs at boot: waits for the network, logs in, allowlists the LAN, enables Meshnet, connects to the first country. |
| `nordvpn_monitor.sh` | Polls every 5 seconds and **speaks** every connection change. |
| `nordvpn_rotate.sh` | Advances one step through `NORDVPN_COUNTRIES`. |
| `nordvpn_connect.sh` | Connects to a named country or server. |
| `nordvpn_disconnect.sh` | Drops the tunnel. |
| `nordvpn_status.sh` | Speaks the current status. |

`nordvpn_monitor.sh` tracks the **hostname** as well as country and city, so
rotating between two servers in the same city (`pl123` → `pl456`) is reported
rather than passing silently. It also pauses for three seconds before
announcing a disconnection, to let DNS fall back to the normal resolver —
speaking immediately after the tunnel drops used to fail with "Temporary
failure in name resolution" and stay silent.

---

## Meshnet — reaching the Pi from anywhere

This is the more useful half, and it needs no router configuration at all.

1. Install NordVPN on your phone or laptop, logged into the **same account**.
2. Enable Meshnet on both.
3. The Pi appears in the device list with a permanent name and IP.

Find the Pi's Meshnet address:

```bash
nordvpn meshnet peer list
```

Then, from anywhere in the world:

```bash
ssh pi@<meshnet-address>
```

Point Kore at the same address to control Kodi remotely. Combined with module
`75-port-forwarding`, devices *behind* the Pi become reachable too.

Nothing here is exposed to the public internet — Meshnet is private to your
NordVPN account.

---

## Verify

```bash
./bin/doctor.sh vpn
```

Checks the daemon, group membership, login state, Meshnet, the allowlist, and
that `NORDVPN_LAN_SUBNET` matches the Pi's actual address.

Manually:

```bash
nordvpn status
nordvpn settings
nordvpn meshnet peer list
```

---

## Troubleshooting

### SSH drops the moment the VPN connects

**The classic failure.** Your LAN subnet is not allowlisted.

Recover from the Pi's console (keyboard, or the physical Pi):

```bash
nordvpn disconnect
```

Then fix it properly:

```bash
nano config.sh                      # correct NORDVPN_LAN_SUBNET
./install.sh 70-nordvpn
```

Verify:

```bash
nordvpn settings | grep -i allow
```

**"Permission denied" from nordvpn commands**

You are not in the `nordvpn` group yet, or you have not logged out since being
added:

```bash
id -nG | grep nordvpn
sudo usermod -aG nordvpn $USER
# then log out and back in
```

**"Whitelist" vs "allowlist"**

NordVPN 3.16 renamed the command. The scripts try `allowlist` first and fall
back to `whitelist`, so both work.

**Token login fails**

Tokens expire. Generate a fresh one at
<https://my.nordaccount.com/dashboard/nordvpn/> → Access token, put it in
`config.sh`, and re-run `./install.sh 70-nordvpn`.

**No VPN connection after boot**

- Check "wait for network" is enabled — `./install.sh 00-base` sets it.
  Otherwise the autostart races `dhcpcd` and loses about half the time.
- Check the first entry in `NORDVPN_COUNTRIES` is not `xx`.
- Check the daemon: `systemctl status nordvpnd`.
- Look at the log by running it by hand: `bash bin/nordvpn_autostart.sh`.

**No spoken announcements**

- Install module `90-speech`.
- Test directly: `bash bin/speech.sh "test"`.
- Check the monitor is running: `pgrep -af nordvpn_monitor.sh`. It starts from
  `autostart.sh`, so over SSH it is normally absent until you reboot.

**The connection is very slow**

- A Pi 3B's Ethernet shares the USB bus and tops out around 100 Mbit/s before
  encryption overhead.
- Try a closer country.
- `nordvpn set technology nordlynx` uses WireGuard, which is significantly
  faster than OpenVPN on a Pi.

**Streaming services still detect the VPN**

Expected — the large services actively block known VPN ranges. Try a different
server in the same country, or accept that some services will not work through
a VPN.

**Meshnet peers do not appear**

- Both devices must be logged into the same account with Meshnet on.
- Check: `nordvpn settings | grep -i meshnet`
- Some networks block the discovery traffic; try mobile data to confirm.
