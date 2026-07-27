# Migrating from the old layout

The earlier version of this project kept every script loose in `/home/pi`,
with the home directory itself as the git repository. This document maps the
old layout onto the new one.

**If you are installing fresh, you do not need this file.**

---

## What changed, and why

| Before | Now | Why |
|---|---|---|
| Scripts loose in `/home/pi` | Everything under one repository directory | The home directory was the git repo, so every download, cache and stray file showed up in `git status`. |
| `bash ui_rotate.sh` (relative paths) | `bash "$REC_BIN/ui_rotate.sh"` | Scripts only worked when the current directory happened to be `~`. Anything launched from Kodi or a button ran with a different cwd. |
| `config.sh` tracked in git | `config.sh` ignored; `config.example.sh` tracked | The tracked file held a live NordVPN token. |
| Install steps scattered in `README.md`, `INSTALL_LOG.txt`, `tvheadend.txt` | `modules/*/install.sh` plus one document each | Instructions existed as fragments, several marked `@TODO`, and nothing verified they had been followed. |
| Stale-lockfile guards | `flock` | A lockfile left behind after an unclean shutdown stopped the watchdog from ever starting again. |
| One Python process per GPIO pin | One process for all pins | Five interpreters at roughly 10 MB each, on a machine with 1 GB shared with the GPU. |
| No verification | `bin/doctor.sh` | Nothing told you whether the system was actually configured correctly. |

---

## File mapping

### Runtime scripts → `bin/`

| Old | New | Notes |
|---|---|---|
| `~/autostart.sh` | `bin/autostart.sh` | Now exits unless on `/dev/tty1`, so SSH logins no longer start UIs. |
| `~/ui_rotate.sh` | `bin/ui_rotate.sh` | Uses an index file instead of generating `/tmp/start_next_ui.sh`. |
| `~/stop_current_ui.sh` | `bin/stop_current_ui.sh` | Records the next UI *before* killing the current one; force-kills after 10s. |
| `~/gpio_commands.sh` | `bin/gpio_buttons.sh` | Reads the button map from `config.sh` rather than hardcoding it. |
| `~/gpio2command.py` | `bin/gpio_buttons.py` | **Renamed.** Now handles all pins in one process. |
| `~/nordvpn_autostart.sh` | `bin/nordvpn_autostart.sh` | Waits for the network; allowlists the LAN subnet. |
| `~/nordvpn_monitor.sh` | `bin/nordvpn_monitor.sh` | Bug fixes — see below. |
| `~/nordvpn_rotate.sh` | `bin/nordvpn_rotate.sh` | |
| `~/nordvpn_connect.sh` | `bin/nordvpn_connect.sh` | |
| `~/nordvpn_disconnect.sh` | `bin/nordvpn_disconnect.sh` | |
| `~/nordvpn_status.sh` | `bin/nordvpn_status.sh` | Prints as well as speaking, so it is usable over SSH. |
| `~/port_forwarding.sh` | `bin/port_forwarding.sh` | Reads `REC_PORT_FORWARDS`; supports several forwards. |
| `~/speech.sh` | `bin/speech.sh` | Skips gracefully when offline; no longer needs `xxd`. |
| `~/speech_text_splitter.py` | `bin/speech_text_splitter.py` | Unchanged. |
| `~/speech_en.sh`, `~/speech_pl.sh` | *removed* | Use `speech.sh en "..."` / `speech.sh pl "..."`. |
| `~/signal_action.sh` | `bin/signal_action.sh` | Resolves bare filenames against `assets/sounds/`. |
| `~/clipboard2chromium.sh` | `bin/clipboard2chromium.sh` | Validates the clipboard is an http(s) URL; sets `DISPLAY`. |
| `~/chromium_kill.sh` | `bin/chromium_kill.sh` | Resets the exit flag instead of deleting `Preferences` wholesale. |
| `~/lxde_set_resolution.sh` | `bin/desktop_set_resolution.sh` | **Renamed.** Reads the mode from `config.sh`; falls back to the detected output. |
| `~/print_temp.sh` | `bin/pi_temp.sh` | **Renamed.** Also reports throttling flags. |
| `~/iptv_streams_checker.py` | `bin/iptv_streams_checker.py` | Unchanged. |
| — | `bin/doctor.sh` | **New.** |

### Assets → `assets/`

| Old | New |
|---|---|
| `~/signal_action.mp3` | `assets/sounds/signal_action.mp3` |
| `~/sounds/*.wav` | `assets/sounds/` |
| `~/iptvsimple_playlist_pl.m3u` | `assets/iptv/` (installed to `~/.local/share/rec-iptv/`) |
| `~/iptvsimple_pl/*.m3u` | `assets/iptv/` |
| `~/shell_command_launcher.menu` | `assets/kodi/shell_command_launcher.menu` |
| `~/plugins/` | `assets/plugins/` |

### Documentation

| Old | New |
|---|---|
| `README.md` (one long file, with `@TODO` gaps) | `README.md` + `INSTALL.md` + `docs/*.md` |
| `INSTALL_LOG.txt` (loose notes) | Split across the modules it referred to; every link it carried is listed in [SOURCES.md](SOURCES.md) |
| `tvheadend.txt` | `docs/25-tvheadend.md` + `modules/25-tvheadend/install.sh` |
| `TODO.txt` | Items fixed; see below |
| `netflix_auth_key/Readme.md` | `docs/20-kodi-addons.md` |
| `plugins/*/Readme.md` | Kept in place, summarised in `docs/20-kodi-addons.md` |

### Where each `INSTALL_LOG.txt` note went

That file was a scratchpad of one-line reminders. For the record:

| Note | Now in |
|---|---|
| Bluetooth audio streaming + PulseAudio as root | [85-bluetooth.md](85-bluetooth.md) — restored as a full module (the Pi as an A2DP *sink*) |
| `usermod -a -G tty pi` (needed for startx) | [30-retropie.md](30-retropie.md), done by the installer |
| `chmod 0744 /dev/tty0` | [40-desktop.md](40-desktop.md) |
| Joystick vendor/product IDs for EmulationStation | [30-retropie.md](30-retropie.md), [HARDWARE.md](HARDWARE.md) |
| `pip3 install pycryptodomex win_inet_pton` | [20-kodi-addons.md](20-kodi-addons.md) — **corrected**: use `apt install python3-pycryptodome`; pip fails under PEP 668, and `win_inet_pton` is Windows-only and was never needed |
| `wiringpi` is deprecated | [60-gpio.md](60-gpio.md) |
| Stopping EmulationStation cleanly (forum link) | [30-retropie.md](30-retropie.md) |
| IPTV and YouTube add-on tutorials | [SOURCES.md](SOURCES.md) |

### Not carried over

These were in the old home directory but are not part of the project:

| Item | Why |
|---|---|
| `assistant/` | A separate voice-assistant experiment, unrelated to the entertainment centre. |
| `public_html/`, `public_html.zip` | Website content, not project code. Keep it in `/var/www/html` or its own repository. |
| `weather.py`, `say_weather_pl.sh`, `movement_detection.py`, `monitor_gpio_pin.py`, `getvolume_*.py` | One-off experiments, not wired into anything. Keep them if you use them; they are not referenced by any module. |
| `youtube_gcp_api_key.txt`, `netflix_auth_key/NFAuthentication.key` | **Secrets.** These belong in the respective Kodi add-ons' own settings, never in the repository. |

---

## Bugs fixed during the move

Some of these were open items in the old `TODO.txt`.

**`nordvpn_monitor.sh` never reported a change of server number.**
The condition required *both* country and city to change:

```bash
if [[ "$country" != "$prev_country" ]] && [[ "$city" != "$prev_city" ]]
```

Rotating `pl123` → `pl456` changed neither, so nothing was announced. The
monitor now tracks the hostname as well, and compares the whole state.

**`nordvpn_monitor.sh` stayed silent about disconnections.**
Speaking immediately after the tunnel dropped failed with `Temporary failure
in name resolution`, because the TTS request went out before DNS had fallen
back to the normal resolver. There is now a short pause, and `speech.sh`
checks connectivity before trying at all.

**Stale lockfiles disabled the watchdog permanently.**
The old guard was "does this file exist?". After an unclean shutdown the file
survived, and `ui_rotate.sh` exited immediately on every subsequent boot —
which looks exactly like a broken UI switcher. Now `flock`, which the kernel
releases when the process dies for any reason.

**Kodi hanging on quit stopped the UI switch.**
`stop_current_ui.sh` sent `Quit` and moved on. A Kodi that did not exit still
looked "running" to the watchdog, so the next UI never started. It now waits
10 seconds and escalates to `SIGKILL`.

**SSH logins started a second set of services.**
`.bashrc` runs for every interactive shell. `autostart.sh` now exits unless it
is on `/dev/tty1`.

**Everything broke if the working directory was not `~`.**
All invocations are now absolute, derived from the script's own location.

---

## How to migrate

**1. Back up the old system**

```bash
# from another machine
mkdir -p backup
scp pi@rpi:~/config.sh                  backup/config.sh.old
rsync -av pi@rpi:~/.kodi/userdata/      backup/kodi-userdata/
rsync -av pi@rpi:~/RetroPie/roms/       backup/roms/
rsync -av pi@rpi:/opt/retropie/configs/ backup/retropie-configs/
scp pi@rpi:~/iptvsimple_playlist_pl.m3u backup/
```

**2. Install the new layout**

You can do this alongside the old one — nothing conflicts except the `.bashrc`
hook, which the installer replaces cleanly.

```bash
cd ~
git clone https://github.com/KusmierczykHobbyPrjs/rpi_entertainment_center.git
cd rpi_entertainment_center
./install.sh 00-base
```

`00-base` detects and removes the old bare `bash autostart.sh &` line from
`.bashrc`, replacing it with the marker block.

**3. Carry your settings across**

The variable names changed. Map them by hand:

| Old | New |
|---|---|
| `uis=(...)` | `REC_UI_PROCESSES=(...)` |
| `ui_start_commands=(...)` | `REC_UI_START=(...)` |
| `ui_commands=(...)` | `REC_UI_STOP=(...)` |
| `default_ui_command="kodi &"` | `REC_UI_DEFAULT_INDEX=0` |
| `VOLUME` | `VOLUME` (unchanged) |
| `ACTION_SOUND` | `ACTION_SOUND` (unchanged) |
| `NORDVPN_TOKEN` | `NORDVPN_TOKEN` (unchanged) |
| `NORDVPN_COUNTRIES` | `NORDVPN_COUNTRIES` (unchanged) |
| — | `REC_UI_NAMES` — **new**, add it |
| — | `NORDVPN_LAN_SUBNET` — **new**, set it |
| hardcoded in `gpio_commands.sh` | `REC_GPIO_BUTTONS` |
| hardcoded in `port_forwarding.sh` | `REC_PORT_FORWARDS` |

```bash
nano config.sh
```

**Do not `declare -a` the arrays.** `config.sh` is sourced from inside a
function, and `declare` there makes them local — the scripts would see empty
arrays and no UI would ever start.

**4. Install the modules you need, then verify**

```bash
./install.sh
./bin/doctor.sh
```

**5. Rotate your NordVPN token**

The old `config.sh` was tracked in git with a live token in it. Removing it
from a later commit does not remove it from history — generate a new token at
<https://my.nordaccount.com/dashboard/nordvpn/> and put that in the new
`config.sh`.

**6. Clean up the old files** once the new system is confirmed working

```bash
mkdir ~/old-project
mv ~/ui_rotate.sh ~/stop_current_ui.sh ~/nordvpn_*.sh ~/speech*.sh \
   ~/gpio*.py ~/gpio_commands.sh ~/port_forwarding.sh ~/autostart.sh \
   ~/config.sh ~/signal_action.sh ~/chromium_kill.sh \
   ~/clipboard2chromium.sh ~/lxde_set_resolution.sh ~/print_temp.sh \
   ~/old-project/ 2>/dev/null
```

Keep `~/old-project` until you are confident, then delete it.

The old repository lived in `/home/pi/.git`. Once you have moved to the new
layout, that can go too — but **back it up first**, since it is the history of
the project:

```bash
tar czf ~/old-repo-backup.tar.gz -C /home/pi .git
```
