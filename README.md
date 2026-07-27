# SmartTV that does not watch you

Turn a Raspberry Pi into a media centre, a retro games console and a desktop
computer — switchable with one button, controllable from your phone, and with
no account, subscription or telemetry in the middle.

Tested on a **Raspberry Pi 3B** running **Raspberry Pi OS (Bullseye and later)**.

---

## Overview

Everything below runs on one Pi, wired to one TV, and is optional — each line
maps to a module you can install or skip.

- **Three full-screen environments on the same device**, one running at a time
  - **Kodi** — films, live TV, radio, streaming services
  - **EmulationStation / RetroPie** — retro gaming
  - **LXDE Desktop** — a real browser for everything the others cannot do
  - a **UI watchdog** that keeps exactly one of them alive, so the TV is never
    left on a black screen
- **Physical buttons on the GPIO header** — switch UI, play/pause, rotate the
  VPN, and power the Pi **off *and* back on** from a single button
- **For Kodi**
  - remote control from a phone using [Kore](https://play.google.com/store/apps/details?id=org.xbmc.kore)
  - internet TV and radio via IPTV, with bundled playlists
  - streaming from YouTube, BBC iPlayer, Finnish Yle, Polish TVP VOD and
    Polsat, and others
  - DRM services (Netflix, Disney+) via third-party add-ons — these depend on
    reverse-engineered private APIs and **break periodically**; the desktop
    browser is the documented fallback
  - broadcast TV, recording and a proper EPG via Tvheadend, if you have a tuner
  - a **shell launcher menu** inside Kodi, so VPN and UI controls are reachable
    without leaving the sofa
- **For the Desktop**
  - remote control from a phone using [KDE Connect](https://kdeconnect.kde.org/)
    — touchpad, keyboard, notifications, clipboard
  - a one-tap command that opens **the URL from your phone's clipboard**
    full-screen in Chromium
  - pinned to a resolution a Pi 3B can actually drive
- **NordVPN, including Meshnet**
  - one-button rotation through a list of countries, with a no-VPN position
  - connection changes **announced out loud**, including drops
  - controllable from the Kodi menu, a phone, or a physical button
  - reach the Pi from anywhere **without opening a single router port**
- **Port forwarding** — make devices *behind* the Pi (an old phone running an
  IP webcam, a NAS, a printer) reachable through it, again without exposing
  them publicly
- **A home web server visible worldwide** — Apache + PHP, a No-IP hostname,
  Let's Encrypt HTTPS and the hardening an internet-facing box needs
- **The Pi as a Bluetooth speaker** — a phone connects to it and plays through
  whatever is wired to the 3.5 mm jack, working under Kodi and the console and
  not just the desktop
- **Spoken status messages** using free Google services — no API key, no
  account, no local voice data
- **Spoken weather reports**, in the same language, for a configured location
  or one detected automatically

No account, no subscription and no telemetry sits between you and any of it.

---

## How it works

The whole design follows from one constraint: **Kodi, EmulationStation and a
desktop each want the entire screen and GPU, so only one can run at a time.**

The Pi therefore boots to a plain console rather than to a desktop. That is
the key decision — it means nothing has claimed the screen yet, and the
project gets to choose what does:

```
boot ──▶ console autologin ──▶ autostart.sh ──┬──▶ ui_rotate.sh   (UI watchdog)
                                              ├──▶ nordvpn_autostart.sh
                                              ├──▶ nordvpn_monitor.sh  (speaks changes)
                                              ├──▶ port_forwarding.sh
                                              └──▶ gpio_buttons.sh     (listens for presses)
```

**Switching UI** is two cooperating scripts. `stop_current_ui.sh` records
which environment comes next, then stops the current one. `ui_rotate.sh` — a
loop that simply asks "is any UI alive?" — notices the gap and starts the
recorded one. Writing the choice down *before* killing anything means an
interrupted switch still leaves a valid target, so the TV cannot get stranded
on a blank screen.

Because the switch is just "run this script", the same action is available
from a GPIO button, from the Kodi menu, from your phone over KDE Connect, or
over SSH — all four paths call the identical script.

**Feedback is audible**, because the screen is usually showing a film. A beep
confirms the instant a button press is accepted; full sentences announce
things you would otherwise have no way to notice, such as the VPN dropping.

**Configuration lives in one file.** `config.sh` holds every setting and
secret — which UIs exist, which pin does what, which countries to cycle
through, which ports to forward. No script hardcodes a path, a port or a
country, and every script locates itself, so the repository can be cloned
anywhere rather than having to sit in your home directory.

**Installation is modular.** Each capability above is one idempotent installer
under `modules/`; running one twice is safe, and skipping one never breaks
another. When you are done, `bin/doctor.sh` checks the whole system and prints
the exact command to fix anything it finds wrong.

The full reasoning, including the failure modes each choice avoids, is in
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Quick start

On a fresh Raspberry Pi OS install:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/KusmierczykHobbyPrjs/rpi_entertainment_center.git
cd rpi_entertainment_center
./install.sh
```

`install.sh` shows a menu of modules. Install `00-base` first, then whichever
of the others you want. Nothing is all-or-nothing — every module is optional
and independent.

Then:

```bash
nano config.sh      # your VPN token, LAN subnet, button map
./bin/doctor.sh     # checks everything and tells you how to fix what is wrong
sudo reboot
```

**[INSTALL.md](INSTALL.md) is the full walkthrough**, from flashing the SD
card to the first boot. Read that if this is your first time.

---

## The modules

Install them in this order; each is a separate `./install.sh <name>` run.

| Module | What it does | Docs |
|---|---|---|
| `00-base` | Core packages, `config.sh`, console autologin, autostart hook | [docs](docs/00-base.md) |
| `10-kodi` | Kodi with streaming, joystick and command-line control | [docs](docs/10-kodi.md) |
| `15-kodi-iptv` | Live TV and radio from IPTV playlists | [docs](docs/15-kodi-iptv.md) |
| `20-kodi-addons` | YouTube, TVP VOD, Yle, Shell Script Launcher, and the DRM services | [docs](docs/20-kodi-addons.md) |
| `25-tvheadend` | DVB tuner backend, recording and EPG | [docs](docs/25-tvheadend.md) |
| `30-retropie` | EmulationStation and emulators | [docs](docs/30-retropie.md) |
| `40-desktop` | LXDE and Chromium at a TV-friendly resolution | [docs](docs/40-desktop.md) |
| `45-kdeconnect` | Phone as touchpad, keyboard and clipboard for the desktop | [docs](docs/45-kdeconnect.md) |
| `50-ui-rotation` | The one-button UI switcher and its watchdog | [docs](docs/50-ui-rotation.md) |
| `60-gpio` | Physical push buttons | [docs](docs/60-gpio.md) |
| `70-nordvpn` | VPN, Meshnet, country rotation, spoken status | [docs](docs/70-nordvpn.md) |
| `75-port-forwarding` | Reach LAN devices through the Pi | [docs](docs/75-port-forwarding.md) |
| `80-webserver` | Apache + PHP + No-IP + HTTPS, publicly reachable | [docs](docs/80-webserver.md) |
| `85-bluetooth` | Use the Pi as a Bluetooth speaker: phone → Pi → 3.5 mm jack | [docs](docs/85-bluetooth.md) |
| `90-speech` | Spoken messages and the action beep | [docs](docs/90-speech.md) |
| `95-weather` | Spoken weather reports, in the configured language | [docs](docs/95-weather.md) |

### Also worth reading

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the pieces fit together, and why
- **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** — every setting in `config.sh`
- **[docs/HARDWARE.md](docs/HARDWARE.md)** — GPIO wiring, the case, the parts list
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — symptom-first fixes
- **[docs/BACKUP.md](docs/BACKUP.md)** — saving and restoring everything a reinstall would lose
- **[docs/SOURCES.md](docs/SOURCES.md)** — the tutorials this is built on, credited and grouped by module
- **[docs/MIGRATION.md](docs/MIGRATION.md)** — moving from the old flat-home-directory layout

---

## Repository layout

```
.
├── install.sh              module installer (start here)
├── config.example.sh       settings template -> copy to config.sh
├── config.sh               your settings and secrets (git-ignored)
│
├── bin/                    everything that runs at runtime
│   ├── autostart.sh            starts all background services at login
│   ├── ui_rotate.sh            watchdog: keeps one UI running
│   ├── stop_current_ui.sh      switch to the next UI
│   ├── gpio_buttons.{sh,py}    physical button listener
│   ├── nordvpn_*.sh            VPN connect / rotate / monitor / status
│   ├── port_forwarding.sh      socat forwarders
│   ├── speech.sh               spoken messages
│   ├── signal_action.sh        the confirmation beep
│   ├── clipboard2chromium.sh   open the phone's clipboard URL on the TV
│   ├── backup.sh               save settings before a reinstall
│   ├── restore.sh              put them back afterwards
│   ├── doctor.sh               health check
│   └── ...
│
├── lib/
│   ├── common.sh           path resolution, config loading, locks, logging
│   └── install_helpers.sh  idempotent apt/file helpers for the installers
│
├── modules/<name>/install.sh    one installer per module
├── docs/                        one document per module, plus the guides above
├── assets/                      sounds, IPTV playlists, Kodi add-on packages
└── photos/                      pictures of the finished build
```

**Scripts work from anywhere.** Every script resolves the repository root from
its own location, so you can clone this to any directory — it does not have to
be your home folder.

---

## If you change something

Four rules keep the above true. Follow them and your addition behaves like the
rest of the system:

1. **Secrets never enter git.** `config.sh` is git-ignored;
   `config.example.sh` is the tracked template. Add new settings to both.
2. **Installers must be safe to re-run.** Use the helpers in
   `lib/install_helpers.sh` — `ensure_block` replaces its marker block instead
   of appending a second copy, which is what makes re-running harmless.
3. **Never hardcode a path.** Source `lib/common.sh` and use `$REC_ROOT`,
   `$REC_BIN`, `$REC_ASSETS`. A script that assumes a directory breaks the
   moment it is called from Kodi or a button, where the working directory is
   not what you expect.
4. **Add a check to `doctor.sh`** — and make it print the command that fixes
   the problem, not just the fact that there is one.

---

## Requirements

- Raspberry Pi 3B or newer (a Pi 4 is noticeably better for 1080p)
- A good power supply — 2.5 A minimum. Under-voltage is the single most common
  cause of "random" instability on a Pi.
- 16 GB or larger SD card (32 GB if you want a lot of ROMs or recordings)
- Wired Ethernet is recommended for streaming; Wi-Fi works
- Optional: USB gamepad, momentary push buttons, a USB DVB tuner

---

## Licence and scope

This is a personal hobby project, shared in case it is useful. The add-ons it
helps you install come from their own authors under their own licences; where
a service needs an account, you bring your own.
