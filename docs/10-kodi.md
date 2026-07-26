# 10-kodi — the media centre

Kodi is the default UI and the part of the system most used. It plays local
files, streams from add-ons, and — with module `15-kodi-iptv` — acts as a live
TV and radio tuner.

```bash
./install.sh 10-kodi
```

**Prerequisites:** `00-base`.

---

## What it installs

| Package | Why |
|---|---|
| `kodi` | The media centre itself. |
| `kodi-inputstream-adaptive` | DASH and HLS playback. **Almost every modern streaming add-on needs this** — without it add-ons install fine and then fail to play anything. |
| `kodi-inputstream-rtmp` | RTMP streams, still used by some IPTV sources. |
| `kodi-peripheral-joystick` | Lets a USB gamepad drive Kodi's menus, so one controller covers Kodi and RetroPie. |
| `kodi-eventclients-kodi-send` | `kodi-send`, the command-line remote used by the GPIO buttons and the UI switcher. |

It also creates `~/.kodi/userdata/advancedsettings.xml` with background library
updates enabled — a Pi 3B is slow at scanning and a foreground scan blocks the
interface.

---

## Finish the setup inside Kodi

Two settings cannot be scripted from outside a running Kodi. Do these once,
with a keyboard or through the Kore app:

**Enable remote control** (required for the Kore phone app):

> Settings → Services → Control
> - **Allow remote control via HTTP** → On (port 8080)
> - **Allow remote control from applications on other systems** → On
> - Set a username and password if the Pi is reachable beyond your LAN

**Allow unknown sources** (required for module `20-kodi-addons`):

> Settings → System → Add-ons → **Unknown sources** → On

---

## The Kore remote

[Kore](https://kodi.tv/addons/omega/plugin.program.kore/) is Kodi's official
phone remote — full navigation, a virtual keyboard, playlist control and
library browsing. It is the primary way this system is driven.

1. Install Kore from the app store on your phone.
2. Enable remote control in Kodi as above.
3. Open Kore — it finds the Pi automatically on the same network.
4. If it does not, add it by hand: the Pi's IP, port 8080, plus the username
   and password if you set one.

**From outside your home**, use the Pi's Meshnet address instead of its LAN
address (module `70-nordvpn`; find it with `nordvpn meshnet peer list`). This
works without opening any router port.

Screenshots of the remote in use: [`photos/kore_remote/`](../photos/kore_remote/).

---

## Controlling Kodi from the command line

`kodi-send` is how the GPIO buttons and the Kodi menu entries talk to Kodi:

```bash
kodi-send -a "PlayerControl(Play)"      # play / pause
kodi-send -a "PlayerControl(Next)"      # next track
kodi-send -a "Action(VolumeUp)"
kodi-send -a "PlayPvrRadio"             # start radio
kodi-send --action="Quit"               # clean shutdown (used by the UI switcher)
```

Full list: <https://kodi.wiki/view/List_of_built-in_functions>

---

## Adding your media

**Local and USB files:** Videos → Files → Add videos… → Browse to the folder.
Set the content type (Movies / TV shows) so Kodi fetches artwork and metadata.

USB drives need the filesystem packages from `00-base` and a mount point; see
[HARDWARE.md § Storage](HARDWARE.md#storage).

**Network shares:** the same dialogue accepts SMB, NFS and UPnP sources.

---

## Verify

```bash
./bin/doctor.sh kodi
```

Start Kodi by hand to check it runs:

```bash
kodi
```

From SSH this fails with a display error — that is expected. Test from the
physical console, or just let the watchdog start it after a reboot.

---

## Troubleshooting

**Video stutters or drops frames**

- Raise the GPU memory split: `sudo raspi-config` → Performance Options → GPU
  Memory → **128**. The default 64 MB is not enough for 1080p on a Pi 3B.
- Check the temperature: `./bin/pi_temp.sh`. Above 80 °C the Pi throttles.
- Check for under-voltage: `vcgencmd get_throttled` should print `0x0`.
- 1080p60 content is beyond a Pi 3B regardless of settings.

**An add-on installs but plays nothing**

Almost always missing adaptive streaming support:

```bash
sudo apt-get install kodi-inputstream-adaptive
```

Then in the add-on's own settings make sure InputStream Adaptive is selected.

**Kore cannot find the Pi**

- Confirm remote control is enabled (Settings → Services → Control).
- Confirm the phone is on the same network — not on a guest VLAN.
- Check the port is open: `ss -tlnp | grep 8080`.
- If the VPN is connected, confirm your LAN subnet is allowlisted — see
  [70-nordvpn.md](70-nordvpn.md). This is the usual cause of a remote that
  worked yesterday.

**Kodi will not quit when you press the switch-UI button**

`stop_current_ui.sh` sends `Quit`, waits 10 seconds, then escalates to
`SIGKILL`. If it happens every time, Kodi is hanging on shutdown — check
`~/.kodi/temp/kodi.log`.

**No sound**

- Force HDMI audio: `sudo raspi-config` → System Options → Audio → HDMI.
- Check the mixer is not muted: `alsamixer`.
- Confirm a card exists: `aplay -l`.

**Where the logs are**

```
~/.kodi/temp/kodi.log         current session
~/.kodi/temp/kodi.old.log     previous session
```
