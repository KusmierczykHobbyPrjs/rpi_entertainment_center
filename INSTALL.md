# Installation — from a blank SD card to a working system

This walkthrough assumes nothing. Follow it top to bottom and you will end up
with a working entertainment centre; skip any module you do not want.

**Time needed:** about 45 minutes of attention, plus up to two hours of
unattended compiling if you install RetroPie.

---

## Contents

1. [Before you start](#1-before-you-start)
2. [Flash Raspberry Pi OS](#2-flash-raspberry-pi-os)
3. [First boot and SSH](#3-first-boot-and-ssh)
4. [System basics](#4-system-basics)
5. [Get this repository](#5-get-this-repository)
6. [Install the base module](#6-install-the-base-module)
7. [Configure](#7-configure)
8. [Install the modules you want](#8-install-the-modules-you-want)
9. [Verify](#9-verify)
10. [First real boot](#10-first-real-boot)
11. [Finishing touches inside Kodi](#11-finishing-touches-inside-kodi)
12. [Set the audio levels](#12-set-the-audio-levels)
13. [Restoring a previous installation](#13-restoring-a-previous-installation)

---

## 1. Before you start

Gather:

- **Raspberry Pi 3B or newer.** A 3B is enough for 720p video, retro gaming up
  to the PlayStation era, and light desktop use. A Pi 4 handles 1080p
  comfortably.
- **A power supply rated 2.5 A or more.** This matters more than anything else
  on this list. An underpowered Pi throttles, drops USB devices and corrupts
  SD cards, and reports none of it as an error. If you take one thing from
  this document, take this.
- **A 16 GB or larger SD card**, class 10 or better. 32 GB if you plan to
  store ROMs or TV recordings.
- **An HDMI cable and a TV.**
- **Ethernet**, ideally. Wi-Fi works but streams less reliably.

Optional, depending on which modules you want:

- USB gamepad (RetroPie)
- 4–5 momentary push buttons and some wire (GPIO control)
- USB DVB-T tuner (Tvheadend)
- A NordVPN subscription (VPN and Meshnet modules)
- A free No-IP account (public web server module)

---

## 2. Flash Raspberry Pi OS

Use the [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

- **OS:** Raspberry Pi OS (32-bit) **with desktop**. You need the desktop
  variant even though the Pi will boot to a console — the desktop is one of
  the three UIs.

  On a Pi 3B choose **32-bit**, not 64-bit: with 1 GB of RAM the 64-bit
  build costs roughly 90 MB more at idle and buys you nothing this project
  uses.
- Click the **gear icon** before writing and set:
  - **Hostname.** The default is `raspberrypi`, so without changing it you
    connect with `ssh <user>@raspberrypi`. Set it to something shorter here
    (e.g. `rpi`) if you would rather — but whatever you choose, use *that*
    everywhere these docs write `raspberrypi`.
  - **Enable SSH** with password authentication. **This is not on by
    default** — if you skip it here, SSH will refuse to connect and you will
    need a keyboard and monitor to turn it on.
  - **Username and password.** There is no default `pi` user any more; the
    Imager makes you create one. These docs write `pi` and `raspberrypi`
    for concreteness — substitute your own. No script depends on either.
  - **Wi-Fi credentials**, if you are not using Ethernet.
  - **Locale and timezone.**

Setting these in the Imager saves you having to attach a keyboard later.

Write the card, put it in the Pi, connect HDMI and Ethernet, and power it on.

---

## 3. First boot and SSH

The first boot takes a few minutes — the filesystem is resized and the Pi
reboots itself once.

From another computer on the same network:

```bash
ssh <your-user>@raspberrypi          # or your chosen hostname
```

Two things commonly go wrong here:

- **"Connection refused"** — SSH was not enabled in the Imager. There is no
  way around this remotely; attach a keyboard and monitor and run
  `sudo raspi-config` → Interface Options → SSH.
- **"Name or service not known"** — mDNS is not resolving. Try
  `<user>@raspberrypi.local`, or find the Pi's IP in your router's device
  list and use that.

The rest of this guide is done over SSH. You do not need a keyboard attached
to the Pi.

---

## 4. System basics

Update everything first. On a fresh image this can take 10–20 minutes.

```bash
sudo apt-get update && sudo apt-get full-upgrade -y
```

Then open the configuration tool:

```bash
sudo raspi-config
```

Set these, if the Imager did not already:

- **System Options → Password** — change it if you kept a default.
- **Localisation Options** — locale, timezone and keyboard layout. A wrong
  timezone shows the wrong times in the TV guide.
- **Advanced Options → Expand Filesystem** — usually already done.
- **Performance Options → GPU Memory** — set **128** on a Pi 3B. Kodi needs
  the video memory; the default 64 MB causes stuttering on 1080p content.

The installer sets boot behaviour and "wait for network" itself, so leave
those alone.

Reboot: `sudo reboot`

---

## 5. Get this repository

```bash
sudo apt-get install -y git
git clone https://github.com/KusmierczykHobbyPrjs/rpi_entertainment_center.git
cd rpi_entertainment_center
```

You can clone this anywhere — the scripts find themselves. `~/rpi_entertainment_center`
is the obvious choice.

---

## 6. Install the base module

Everything else depends on this one. It installs the shared packages, creates
your `config.sh`, sets the Pi to boot to a console with autologin, and hooks
the autostart script into your login shell.

```bash
./install.sh 00-base
```

> **Do not run the installer with `sudo`.** It calls `sudo` itself for the few
> steps that need it. Running the whole thing as root would leave root-owned
> files scattered through your home directory.

### Why console autologin?

Because the project decides which UI starts, and it cannot do that if the
system has already started one. Booting to a plain console lets
`autostart.sh` run first and hand control to Kodi, EmulationStation or the
desktop as appropriate.

---

## 7. Configure

```bash
nano config.sh
```

Everything has a working default. The settings you should actually look at
now:

| Setting | Why |
|---|---|
| `NORDVPN_LAN_SUBNET` | **Get this right.** If it does not match your network, SSH drops the moment the VPN connects. |
| `NORDVPN_TOKEN` | Needed for automatic VPN login at boot. |
| `NORDVPN_COUNTRIES` | The list the VPN button cycles through. |
| `REC_GPIO_BUTTONS` | Only if you are wiring physical buttons. |
| `REC_PORT_FORWARDS` | Only if you want to reach LAN devices through the Pi. |
| `VOLUME` | Volume of spoken messages, as a percentage. |

Find your LAN subnet with:

```bash
ip route | grep -v default | grep "$(hostname -I | awk '{print $1}' | cut -d. -f1-3)"
```

Typically `192.168.1.0/24` or `192.168.0.0/24`.

**[docs/CONFIGURATION.md](docs/CONFIGURATION.md) documents every setting.**

`config.sh` is git-ignored and holds your VPN token, so keep it at mode 600
(the installer does this for you).

---

## 8. Install the modules you want

Run the menu and pick:

```bash
./install.sh
```

…or name the ones you want, in order. **These are examples, not a script to
run top to bottom** — install only the modules you actually want:

```bash
./install.sh 00-base                     # required, first
./install.sh 10-kodi 15-kodi-iptv        # media centre + live TV
./install.sh 90-speech                   # before the VPN, so it can talk
./install.sh 40-desktop                  # only if you want the desktop UI
./install.sh 50-ui-rotation              # LAST of the UI modules - it checks
                                         # that the UIs in config.sh exist
```

`50-ui-rotation` must come after the UI modules, and `00-base` before
everything. Otherwise order is up to you.

Recommended order and what each costs you in time:

| Order | Module | Time | Notes |
|---|---|---|---|
| 1 | `00-base` | 5 min | Required. |
| 2 | `10-kodi` | 10 min | The media centre. |
| 3 | `15-kodi-iptv` | 2 min | Live TV and radio. |
| 4 | `20-kodi-addons` | 2 min | Stages the add-on packages; you finish inside Kodi. |
| 5 | `90-speech` | 2 min | Do this before the VPN module so it can talk. |
| 6 | `40-desktop` | 10 min | Only if you want the third UI. |
| 7 | `45-kdeconnect` | 5 min | Needs `40-desktop`. |
| 8 | `30-retropie` | **45–120 min** | Compiles emulators. Start it and walk away. |
| 9 | `50-ui-rotation` | 1 min | Run this **after** installing the UIs you want. |
| 10 | `60-gpio` | 2 min | Only with buttons wired. |
| 11 | `70-nordvpn` | 5 min | Needs a subscription. |
| 12 | `75-port-forwarding` | 2 min | Needs `70-nordvpn` to be useful. |
| 13 | `25-tvheadend` | 5 min | Only with a TV tuner. |
| 14 | `80-webserver` | 15 min | **Exposes the Pi to the internet** — read the doc first. |

`50-ui-rotation` deliberately comes late: it checks that the UIs listed in
`config.sh` are actually installed, which it can only do once they are.

Install everything unattended with:

```bash
./install.sh --all --yes
```

---

## 9. Verify

```bash
./bin/doctor.sh
```

This checks every module and prints, for each problem, the exact command that
fixes it. Work through the `FAIL` lines. `WARN` lines are usually fine — over
SSH it is normal to see "no UI is running" and "the watchdog is not running",
because those only start on the physical console.

Check one area at a time with e.g. `./bin/doctor.sh vpn`.

---

## 10. First real boot

```bash
sudo reboot
```

What should happen on the TV:

1. Console text scrolls past.
2. The Pi logs in automatically.
3. Kodi starts (or whichever UI is at `REC_UI_DEFAULT_INDEX`).
4. If the VPN is configured, you hear it announce the country it connected to.

If the screen stays black, see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#nothing-appears-on-the-tv) —
SSH still works, so this is recoverable.

---

## 11. Finishing touches inside Kodi

Some things cannot be scripted from outside a running Kodi. These are one-time
jobs, and **all of them are needed** — skipping one is the usual reason
something "does not work" later.

### 11.1 Turn on remote control — do this first

**Without this the Kore phone app cannot connect at all.** Do it before the
rest, because once it works you can use your phone to do everything below
instead of hunting for a keyboard.

> Settings → Services → **Control**
> - **Allow remote control via HTTP** → **On**  (port 8080)
> - **Allow remote control from applications on other systems** → **On**
> - Set a username and password if the Pi is reachable beyond your LAN

Then install [Kore](https://play.google.com/store/apps/details?id=org.xbmc.kore) on your
phone. It finds the Pi automatically on the same network; if not, add it by
hand with the Pi's IP, port 8080, and those credentials.

Verify from another machine:

```bash
curl -s -u kodi:PASSWORD \
  'http://<pi-ip>:8080/jsonrpc?request={"jsonrpc":"2.0","method":"JSONRPC.Ping","id":1}'
```

A `"pong"` back means it is working.

### 11.2 Allow add-ons from outside the official repository

Needed for everything in module `20-kodi-addons`:

> Settings → System → Add-ons → **Unknown sources** → **On**

### 11.3 Install the add-ons

The installer staged them in `~/kodi-addons-to-install`:

> Settings → Add-ons → **Install from zip file** → Home folder →
> `kodi-addons-to-install`

Start with `repository.linuxaddons-1.0.1.zip`, then install **Shell Script
Launcher** from that repository and point it at `~/shell_command_launcher.menu`
(the installer prints the full path). That is what puts VPN and UI switching
inside Kodi.

### 11.4 Point the IPTV client at a playlist

> Settings → Add-ons → My add-ons → PVR clients → **PVR IPTV Simple Client** →
> Configure
> - General → M3U play list path:
>   `~/.local/share/rec-iptv/iptvsimple_playlist_pl.m3u`
> - Advanced → User agent: `Mozilla/5.0`

Then **enable** the add-on and restart Kodi. Without the user agent many public
streams answer 403 and simply refuse to play.

Full details in [docs/20-kodi-addons.md](docs/20-kodi-addons.md) and
[docs/15-kodi-iptv.md](docs/15-kodi-iptv.md).

---

## 12. Set the audio levels

**Do not skip this.** Volume on this system is a chain of multiplications:

```
Kodi volume  ×  PipeWire stream  ×  PipeWire sink  ×  ALSA PCM  =  output
```

Every stage multiplies, so Kodi at 100% into an ALSA control sitting at 40%
gives you 40%. A fresh install commonly leaves ALSA low, and the symptom is
"the volume is at maximum and it is still quiet".

Module `90-speech` offers to set these for you. To do it by hand:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%
wpctl set-mute   @DEFAULT_AUDIO_SINK@ 0
```

> **Use `wpctl`, not `amixer`.** On Bookworm and later, WirePlumber owns the
> hardware mixer and re-applies its own remembered volume at every startup. A
> level set with `amixer` — even followed by `sudo alsactl store` — is
> overwritten on the next boot, which shows up as `alsamixer` mysteriously
> dropping back to where it was. `wpctl` values are persisted by WirePlumber
> itself, with nothing extra to run.
>
> On a system with no PipeWire, `amixer sset PCM 100% && sudo alsactl store`
> is the correct pair.

Check all stages at once:

```bash
./bin/doctor.sh audio
```

### If it is still quiet

The Pi's 3.5 mm jack is not a DAC — it is PWM from two GPIO pins through a
passive filter, well below line level and audibly noisy.

- Add `audio_pwm_mode=2` to `/boot/firmware/config.txt` and reboot — a real
  signal-to-noise improvement.
- PipeWire will go above 100% (`wpctl set-volume @DEFAULT_AUDIO_SINK@ 150%`),
  which is genuine amplification at the cost of clipping.
- **Better: use HDMI audio** if your TV or receiver can take it. It bypasses
  the jack entirely, costs nothing, and sounds far better —
  `sudo raspi-config` → System Options → Audio → HDMI.
- Otherwise a £10–20 USB DAC fixes both level and noise floor.

Full detail in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#sound-is-too-quiet-even-at-maximum-volume).

---

## 13. Restoring a previous installation

Reinstalling and want your old settings back? These are the things worth
keeping from the old system, and where they belong on the new one:

| What | Old location | New location |
|---|---|---|
| Your settings and VPN token | `~/config.sh` | `<repo>/config.sh` |
| Kodi library, add-on settings, favourites | `~/.kodi/userdata/` | same |
| Installed Kodi add-ons | `~/.kodi/addons/` | same |
| ROMs | `~/RetroPie/roms/` | same |
| Emulator and controller config | `/opt/retropie/configs/` | same |
| IPTV playlists | `~/iptvsimple_*.m3u` | `~/.local/share/rec-iptv/` |
| Web server content | `/var/www/html/` | same |
| Tvheadend config | `/home/hts/.hts/` | same |

`bin/backup.sh` collects all of this into one archive — run it **before**
wiping the card:

```bash
bin/backup.sh                                  # settings, ~10 MB
scp pi@rpi:~/rec-backups/rec-backup-*.tar.gz . # copy it somewhere safe
```

ROMs are excluded by default because they are usually gigabytes. Take them
separately, or use `bin/backup.sh --with-content`:

```bash
rsync -av --info=progress2 pi@rpi:~/RetroPie/roms/ ./roms-backup/
```

Afterwards, **install the modules first, then restore** — RetroPie's setup
recreates `/opt/retropie/configs` and the installers rewrite `config.sh`, so
restoring first would be undone:

```bash
./install.sh 00-base 10-kodi 30-retropie
bin/restore.sh rec-backup-settings-*.tar.gz
bin/doctor.sh
```

Full details, including restoring only part of an archive:
**[docs/BACKUP.md](docs/BACKUP.md)**.

If you are moving from the older version of this project — where every script
sat loose in the home directory — read
[docs/MIGRATION.md](docs/MIGRATION.md). It maps every old file to its new
home.

---

## Where to go next

- Something not working? → [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- Want to understand the design? → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Wiring buttons? → [docs/HARDWARE.md](docs/HARDWARE.md)
- Tuning a setting? → [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
