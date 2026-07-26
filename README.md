# SmartTV that does not watch you

Turn a Raspberry Pi into a media centre, a retro games console and a desktop
computer — switchable with one button, controllable from your phone, and with
no account, subscription or telemetry in the middle.

Tested on a **Raspberry Pi 3B** running **Raspberry Pi OS (Bullseye and later)**.

---

## What you get

**Three environments on one device**, one running at a time:

| | | |
|---|---|---|
| **Kodi** | media centre | films, live TV, radio, streaming services |
| **RetroPie** | retro gaming | EmulationStation and the usual emulators |
| **Desktop** | LXDE | a real browser for everything else |

Press one physical button (or pick a menu entry in Kodi) to cycle between
them. A watchdog makes sure one is always running, so the TV is never left
showing a black screen.

**Controlled without a keyboard**

- **Kodi** from the [Kore](https://kodi.tv/addons/omega/plugin.program.kore/) app on your phone
- **Desktop** from [KDE Connect](https://kdeconnect.kde.org/) — touchpad, keyboard, and a
  "copy a link on your phone, open it full-screen on the TV" command
- **RetroPie** from any USB gamepad
- **Everything** from physical buttons wired to the GPIO header

**Networking that stays private**

- **NordVPN** with one-button country rotation and spoken status announcements
- **Meshnet** so you can reach the Pi from anywhere without opening a single
  port on your router
- **Port forwarding** so devices *behind* the Pi (an old phone running an IP
  webcam, a NAS, a printer) become reachable too — again without exposing
  them publicly
- Optionally, a **public web server** with a No-IP hostname and HTTPS

**Feedback you can hear**, because the screen is usually showing a film: the
Pi speaks status changes out loud and beeps when it accepts a button press.

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
| `20-kodi-addons` | YouTube, Netflix, TVP VOD, Yle, Shell Script Launcher | [docs](docs/20-kodi-addons.md) |
| `25-tvheadend` | DVB tuner backend, recording and EPG | [docs](docs/25-tvheadend.md) |
| `30-retropie` | EmulationStation and emulators | [docs](docs/30-retropie.md) |
| `40-desktop` | LXDE and Chromium at a TV-friendly resolution | [docs](docs/40-desktop.md) |
| `45-kdeconnect` | Phone as touchpad, keyboard and clipboard for the desktop | [docs](docs/45-kdeconnect.md) |
| `50-ui-rotation` | The one-button UI switcher and its watchdog | [docs](docs/50-ui-rotation.md) |
| `60-gpio` | Physical push buttons | [docs](docs/60-gpio.md) |
| `70-nordvpn` | VPN, Meshnet, country rotation, spoken status | [docs](docs/70-nordvpn.md) |
| `75-port-forwarding` | Reach LAN devices through the Pi | [docs](docs/75-port-forwarding.md) |
| `80-webserver` | Apache + PHP + No-IP + HTTPS, publicly reachable | [docs](docs/80-webserver.md) |
| `90-speech` | Spoken messages and the action beep | [docs](docs/90-speech.md) |

### Also worth reading

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the pieces fit together, and why
- **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** — every setting in `config.sh`
- **[docs/HARDWARE.md](docs/HARDWARE.md)** — GPIO wiring, the case, the parts list
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — symptom-first fixes
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

## Design principles

Worth knowing before you change anything:

1. **Modules are independent and idempotent.** Installing one twice is safe.
   Skipping one never breaks another. Re-running after an edit picks up the
   change.
2. **Configuration lives in one file.** `config.sh` holds every setting and
   every secret. No script hardcodes a path, a port or a country.
3. **Secrets never enter git.** `config.sh` is git-ignored;
   `config.example.sh` is the tracked template.
4. **Nothing assumes a directory.** Scripts locate themselves; the repo can
   live anywhere.
5. **Failures are audible.** A system with no visible shell has to tell you
   what went wrong out loud.
6. **Every check says how to fix itself.** `doctor.sh` never reports a problem
   without printing the command that resolves it.

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
