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

## Starting Kodi without a desktop

> **This is the single most common reason Kodi never appears at boot.**

Debian ships several Kodi front-ends, and the bare `kodi` command is a
**wrapper that prefers the X11 build**. Started from tty1 with no X server
running, it cannot work.

| Command | Works from a console? |
|---|---|
| `kodi` | **No** — needs an X server already running |
| `kodi-standalone` | Yes — brings up its own minimal session |
| `kodi-gbm` | Yes — renders directly through KMS, no X at all |

So `REC_UI_START` must **not** be `kodi &`:

```bash
REC_UI_START=("kodi-standalone &" ...)
```

The installer detects which front-ends you have and prints the right value.
`./bin/doctor.sh ui` fails if `config.sh` names plain `kodi` while a
console-capable build is present.

### Process name

The watchdog identifies a running UI by process name, and what Kodi is *called*
often differs from the command that started it — `kodi-standalone` typically
becomes `kodi.bin`. Check after it starts:

```bash
ps -A | grep -i kodi
```

`REC_UI_PROCESSES[0]="kodi"` is the safest value: the matcher falls back to a
command-line match, so it catches `kodi.bin`, `kodi-gbm` and `kodi-standalone`
alike. A name that matches nothing makes the watchdog relaunch Kodi every ten
seconds, which looks exactly like Kodi refusing to start.

---

## Group membership

Kodi started from a console has no desktop session behind it. It reaches the
GPU through `/dev/dri` directly, opens input devices itself, and must own the
terminal — so your user needs:

| Group | For |
|---|---|
| `video`, `render` | `/dev/dri` — the GPU |
| `input` | keyboard, remote, gamepad |
| `tty` | owning the console |
| `audio` | the sound device |

Without them Kodi exits immediately with a permissions error that explains
nothing. Module `10-kodi` grants them:

```bash
./install.sh 10-kodi
sudo reboot          # group changes only apply at next login
```

> These used to be granted only by the RetroPie module, so a Kodi-only install
> silently lacked them. If you installed before that was fixed, re-run
> `./install.sh 10-kodi`.

Check:

```bash
id -nG | tr ' ' '\n' | grep -E 'video|render|input|tty|audio'
```

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

[Kore](https://play.google.com/store/apps/details?id=org.xbmc.kore) is Kodi's official
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

Kodi's own site: <https://kodi.tv/>

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

Start Kodi by hand to check it runs — **from the physical console**, using the
console-capable front-end:

```bash
kodi-standalone
```

Over SSH this fails with a display error; that is expected and says nothing
about whether it works at boot. `bin/diagnose.sh --try` runs the configured
start command and captures its output, which is the quickest way to see a real
error.

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

**Kodi never appears at boot**

Work through, in order:

1. `REC_UI_START` must be `kodi-standalone &`, not `kodi &` — see above.
2. Your user must be in `video`, `render`, `input`, `tty`.
3. Check the log: `cat ~/.local/state/rec/autostart.log`
4. Full picture: `./bin/diagnose.sh` (and `--try` on the console).

**Kodi will not quit when you press the switch-UI button**

`stop_current_ui.sh` sends `Quit`, waits 10 seconds, then escalates to
`SIGKILL`. If it happens every time, Kodi is hanging on shutdown — check
`~/.kodi/temp/kodi.log`.

**Squares (□) instead of characters — in weather, titles or menus**

A "tofu box" means the font has no glyph for that character. Kodi's default
Estuary font ships a limited set, so degree signs, separators, and accented or
non-Latin characters can all come out as boxes.

> **Settings → Interface → Skin → Fonts → change `Default` to `Arial based`**

That covers a much wider glyph range and applies immediately. It is the fix
for essentially every missing-character report in Kodi, and is worth setting
straight away if you use a non-English locale.

If a box persists in one add-on only, that add-on is emitting a character even
the Arial-based font lacks — worth reporting upstream rather than chasing
locally.

> Not to be confused with module `95-weather`, which is the *spoken* weather
> and shares no code with Kodi's weather display.

**No sound**

- Force HDMI audio: `sudo raspi-config` → System Options → Audio → HDMI.
- Check the mixer is not muted: `alsamixer`.
- Confirm a card exists: `aplay -l`.

**Where the logs are**

```
~/.kodi/temp/kodi.log         current session
~/.kodi/temp/kodi.old.log     previous session
```
