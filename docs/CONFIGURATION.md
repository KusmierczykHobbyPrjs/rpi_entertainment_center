# Configuration reference

Every setting lives in one file: **`config.sh`** in the repository root.

```bash
cp config.example.sh config.sh    # the installer does this for you
chmod 600 config.sh               # it holds your VPN token
nano config.sh
```

`config.sh` is git-ignored. `config.example.sh` is the tracked template — keep
them in step when you add a setting.

**After editing, changes take effect:**

| Setting group | Applies when |
|---|---|
| `VOLUME`, `ACTION_SOUND`, `SPEECH_LANG` | immediately (read per invocation) |
| `NORDVPN_*` | next time the relevant script runs |
| `REC_UI_*` | next reboot, or restart `ui_rotate.sh` |
| `REC_GPIO_BUTTONS` | next reboot, or restart `gpio_buttons.sh` |
| `REC_PORT_FORWARDS` | next reboot, or restart `port_forwarding.sh` |
| `REC_DESKTOP_*` | next desktop session |
| `REC_WEATHER_*`, `OPENWEATHER_API_KEY` | immediately (read per invocation) |

Verify any change with `./bin/doctor.sh`.

## Overriding a setting for one run

The environment beats `config.sh`, so you can override any single setting
without editing the file:

```bash
VOLUME=0 bash bin/say_weather.sh              # run it silently
SPEECH_LANG=pl bash bin/nordvpn_status.sh     # answer in Polish this once
REC_WEATHER_LOCATION=Helsinki bash bin/say_weather.sh
```

This works because `rec_load_config` snapshots the exported environment before
sourcing `config.sh` and re-applies it afterwards. Useful for testing a change
before committing to it.

---

## User interfaces

Four **parallel arrays** — index 0 of each describes the same UI. They must
always have the same number of entries; `doctor.sh` checks this.

```bash
REC_UI_PROCESSES=("kodi" "emulationstatio" "labwc")
REC_UI_NAMES=("Kodi" "RetroPie" "Desktop")
REC_UI_START=("kodi-standalone &" "emulationstation &" "labwc-pi &")
REC_UI_STOP=("kodi-send --action=\"Quit\"" "pkill emulationstatio" "pkill -x labwc")
REC_UI_DEFAULT_INDEX=0
```

| Array | Meaning |
|---|---|
| `REC_UI_PROCESSES` | Process name as it appears in `ps -A`. Used to detect what is running. |
| `REC_UI_NAMES` | Human-readable name, used in logs and spoken messages. |
| `REC_UI_START` | Command that starts the UI. Keep the trailing `&`. |
| | **Kodi:** use `kodi-standalone`, not `kodi` — the bare wrapper needs an X server and cannot start from a console. |
| | **Desktop:** start the *session*, not the compositor — `labwc-pi` under Wayland (default) or `startx-rpd` under X11. Plain `labwc`/`startx` gives a black screen with no panel. Check which you have with `raspi-config nonint get_wayland`. |
| `REC_UI_STOP` | Command that cleanly stops it. |
| `REC_UI_DEFAULT_INDEX` | Which UI starts on boot (`0` = the first). |

**`emulationstatio` is not a typo** — Linux truncates process names at 15
characters.

**Do not add `declare -a`.** These arrays are read from inside a function, and
`declare` there would make them local; the scripts would see empty arrays and
no UI would ever start.

### Using only some of the UIs

Delete the same index from all four arrays. Kodi only:

```bash
REC_UI_PROCESSES=("kodi")
REC_UI_NAMES=("Kodi")
REC_UI_START=("kodi-standalone &")
REC_UI_STOP=("kodi-send --action=\"Quit\"")
REC_UI_DEFAULT_INDEX=0
```

With a single entry the switch button becomes a restart button, which is a
genuinely useful thing to have on a device with no keyboard.

### Finding the right process name

Start the UI, then from another terminal:

```bash
ps -A | grep -i <name>
```

Use exactly what appears in the right-hand column.

---

## Audio feedback

```bash
export VOLUME=30
export ACTION_SOUND="signal_action.mp3"
export SPEECH_LANG="en"
```

| Setting | Meaning |
|---|---|
| `VOLUME` | Playback volume for beeps and speech, 0–100. Applied by the player itself, so it does not affect film volume. |
| `ACTION_SOUND` | Confirmation beep. A bare filename is looked up in `assets/sounds/`; an absolute path is used as-is. `""` disables beeps. |
| `SPEECH_LANG` | Default language for spoken messages (ISO 639-1: `en`, `pl`, `fi`, `de`, …). |

`VOLUME=30` is a sensible default: announcements should be audible over a film
without being startling at night.

---

## NordVPN

```bash
export NORDVPN_COUNTRIES="xx pl fi uk"
export NORDVPN_LAN_SUBNET="192.168.1.0/24"
export NORDVPN_MESHNET="on"
export NORDVPN_TOKEN=""
```

### `NORDVPN_COUNTRIES`

The list the VPN button cycles through, in order, wrapping at the end.

- Two-letter country codes: `pl`, `fi`, `uk`, `us`, `de`
- A specific server: `uk2431`
- **`xx` means "disconnected"** — include it to get a no-VPN position in the
  rotation

`"xx pl fi uk"` gives: no VPN → Poland → Finland → UK → no VPN → …

If the **first** entry is `xx`, the VPN does not connect at boot.

### `NORDVPN_LAN_SUBNET`

**The most important setting in this file.**

Connecting the VPN routes all traffic into the tunnel — including traffic to
your own network. Without this allowlist entry, SSH drops, the Kore remote
stops working and every port forward dies the moment the VPN connects.

Find yours:

```bash
ip route | grep -v default | grep "$(hostname -I | awk '{print $1}' | cut -d. -f1-3)"
```

Usually `192.168.1.0/24` or `192.168.0.0/24`.

`doctor.sh` cross-checks this against the Pi's actual address and fails loudly
if they disagree.

### `NORDVPN_TOKEN`

Generate at <https://my.nordaccount.com/dashboard/nordvpn/> → **Access token**.

Needed for automatic login at boot. Leave empty and run `nordvpn login` by
hand instead — the VPN still works, it just will not log itself back in after
a token expiry.

This is why `config.sh` is git-ignored and mode 600.

### `NORDVPN_MESHNET`

`"on"` enables Meshnet, which is what makes the Pi reachable from your other
devices without opening any router ports. Set to anything else to skip it.

---

## Port forwarding

```bash
REC_PORT_FORWARDS=(
    "8282:192.168.1.20:8080"
)
```

Format: `LISTEN_PORT:TARGET_HOST:TARGET_PORT`. One entry per line; add as many
as you like:

```bash
REC_PORT_FORWARDS=(
    "8282:192.168.1.20:8080"    # IP webcam on an old Android phone
    "8283:192.168.1.30:80"      # NAS web interface
    "9100:192.168.1.40:9100"    # network printer
)
```

The Pi then relays `pi:8282` to `192.168.1.20:8080`, so the device is
reachable through the Pi's Meshnet address from anywhere.

**These forwards carry no authentication of their own.** That is fine over
Meshnet, which is private to your NordVPN account. Do not forward the same
ports on your router unless the device behind them has its own password.

---

## GPIO buttons

```bash
REC_GPIO_BUTTONS=(
    "3:sudo shutdown now"
    "4:bash $REC_BIN/stop_current_ui.sh"
    "17:bash $REC_BIN/nordvpn_rotate.sh"
    "22:kodi-send -a PlayerControl(Play)"
    "27:kodi-send -a PlayPvrRadio"
)
```

Format: `BCM_PIN:command with arguments`.

- Pin numbers are **BCM** numbering, not physical header positions. See
  [HARDWARE.md](HARDWARE.md).
- `$REC_BIN` expands to this repository's `bin/` directory.
- Commands are tokenised with `shlex`, not run through a shell, so a stray
  character cannot become shell injection. This also means shell syntax
  (pipes, `&&`, redirection) does not work — wrap it in a script if you need
  that.
- `sudo shutdown now` works without a password because module `60-gpio`
  installs a narrowly-scoped sudoers rule for exactly the power commands.

Useful commands to bind:

| Command | Effect |
|---|---|
| `bash $REC_BIN/stop_current_ui.sh` | next UI |
| `bash $REC_BIN/stop_current_ui.sh prev` | previous UI |
| `bash $REC_BIN/nordvpn_rotate.sh` | next VPN country |
| `bash $REC_BIN/nordvpn_status.sh` | speak the VPN status |
| `kodi-send -a PlayerControl(Play)` | play / pause |
| `kodi-send -a PlayerControl(Next)` | next track |
| `kodi-send -a Action(VolumeUp)` | volume up |
| `kodi-send -a PlayPvrRadio` | start radio |
| `sudo shutdown now` | power off |
| `sudo reboot` | restart |

Kodi's full action list: <https://kodi.wiki/view/List_of_built-in_functions>

---

## Desktop

```bash
export REC_DESKTOP_OUTPUT="HDMI-1"
export REC_DESKTOP_MODE="1360x768"
export REC_DESKTOP_RATE="60"
```

LXDE otherwise picks the highest mode the TV advertises, and a Pi 3B cannot
play video in a browser at 1080p. This pins the desktop — and only the desktop
— to something it can drive; Kodi and RetroPie set their own modes.

List what your TV actually supports:

```bash
DISPLAY=:0 xrandr
```

Output names differ between display drivers (`HDMI-1` vs `HDMI-A-1`). If the
configured name is not found, the script falls back to the first connected
output and tells you what to set.

---

## Weather

```bash
export REC_WEATHER_LOCATION="auto"
export REC_WEATHER_UNITS="metric"
export OPENWEATHER_API_KEY=""
```

| Setting | Meaning |
|---|---|
| `REC_WEATHER_LOCATION` | `"auto"` (detect from the public IP), a city (`"Helsinki"`, or `"Cambridge,GB"` to disambiguate), or `"60.17,24.94"` coordinates. |
| `REC_WEATHER_UNITS` | `metric` for Celsius, `imperial` for Fahrenheit. |
| `OPENWEATHER_API_KEY` | Free key from <https://openweathermap.org/api>. A new key can take a couple of hours to activate. |

The spoken language follows `SPEECH_LANG` — there is nothing separate to set.

> **`"auto"` follows your VPN.** IP geolocation reports where your traffic
> leaves the internet, so with the tunnel up it reports the exit country. Set a
> fixed city if you use the VPN. `doctor.sh weather` warns when it sees both.

See [95-weather.md](95-weather.md).

---

## Secrets

`config.sh` contains your NordVPN token, which is why:

- it is in `.gitignore`
- the installer sets it to mode 600
- `doctor.sh` warns if the permissions are looser

Other secrets this project can involve, and where they belong — **none of
these should ever be committed**:

| Secret | Where it goes |
|---|---|
| NordVPN token | `config.sh` → `NORDVPN_TOKEN` |
| OpenWeatherMap key | `config.sh` → `OPENWEATHER_API_KEY` |
| YouTube add-on API key | entered in the Kodi add-on's own settings |
| Netflix authentication key | `~/.kodi/userdata/addon_data/plugin.video.netflix/` |
| No-IP account credentials | `/usr/local/etc/no-ip2.conf` (written by `noip2 -C`) |
| Tvheadend admin password | Tvheadend's own config, set during `apt install` |

`.gitignore` already covers `config.sh`, `secrets/`, `*.key` and
`*_api_key.txt`. If you ever committed one by accident, rotate it — removing
the file from a later commit does not remove it from history.

---

## Checking your configuration

```bash
./bin/doctor.sh
```

It validates array lengths, checks that every configured UI and button command
actually exists, confirms the VPN subnet matches the Pi's address, and prints
the fix for anything wrong.
