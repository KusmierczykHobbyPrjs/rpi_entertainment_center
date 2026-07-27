# Architecture

How the pieces fit together, and why they are arranged this way. Read this if
you want to modify the project rather than just install it.

---

## The core idea

A Raspberry Pi can run Kodi, or EmulationStation, or a desktop — but not two
at once, because each of them wants the whole screen and the whole GPU.

So the system runs **exactly one UI at a time** and makes switching between
them a single action. Everything else is built around that:

```
                       ┌─────────────────────┐
   boot ──▶ autologin ─▶│    autostart.sh     │
   (tty1)               └──────────┬──────────┘
                                   │ starts, in the background
        ┌──────────────┬───────────┼───────────┬─────────────────┐
        ▼              ▼           ▼           ▼                 ▼
  ui_rotate.sh   nordvpn_       nordvpn_    port_          gpio_buttons.sh
  (watchdog)     autostart.sh   monitor.sh  forwarding.sh   (button listener)
        │
        │ "nothing is running — start something"
        ▼
  ┌──────────┐   button    ┌──────────────┐
  │   Kodi   │────────────▶│ stop_current │
  └──────────┘   press     │    _ui.sh    │
        ▲                  └──────┬───────┘
        │                         │ writes the next index to
        │                         ▼
        │              /tmp/rec-next-ui-index
        │                         │
        └─────────────────────────┘  ui_rotate.sh reads it and starts that UI
```

---

## Why boot to a console

`raspi-config` is set to **Console Autologin**, not desktop autologin.

If the Pi booted straight to the desktop, the desktop would already own the
screen and the project would have no say in what runs. Booting to a plain
console means `~/.bashrc` runs first, `autostart.sh` runs from it, and the
watchdog gets to make the decision.

This is also why the autostart hook lives in `.bashrc` rather than in a
systemd unit: it has to run **as the logged-in user, in the session that owns
tty1**. A systemd service runs too early and in the wrong session to start an
X server or Kodi.

The consequence is that `.bashrc` runs on *every* interactive shell, including
every SSH login. `autostart.sh` therefore checks `tty` first and exits
immediately unless it is on `/dev/tty1`. Without that check, logging in over
SSH would start a second Kodi on a screen you cannot see.

---

## The UI switcher

Two scripts, deliberately kept separate:

**`ui_rotate.sh`** — the watchdog. Loops forever, once per second:

- Is any process from `REC_UI_PROCESSES` alive? Then do nothing.
- Nothing alive? Read `/tmp/rec-next-ui-index` (falling back to
  `REC_UI_DEFAULT_INDEX`), start that UI, and wait 10 seconds before checking
  again so a slow-starting Kodi is not started twice.

**`stop_current_ui.sh`** — the switcher. Runs once, when a button is pressed:

- Find which UI is running.
- Write the *next* index to the state file — **before** killing anything, so
  an interrupted switch still leaves a valid choice.
- Stop the current UI with its configured stop command.
- Wait up to 10 seconds for it to exit; escalate to `SIGKILL` if it does not.
  Kodi's clean quit occasionally hangs, and a hung Kodi looks to the watchdog
  like a running UI, so the button appears to do nothing at all.

Splitting them this way means the button handler is short and always
terminates, while the long-running loop has one job.

### Why process names, not PIDs

The watchdog identifies UIs by process name (`pgrep -x kodi`) rather than by
tracking PIDs, because UIs are also started by other things — RetroPie's own
menus, a user typing `startx`, Kodi restarting itself after a settings change.
Name matching notices all of them.

The name `emulationstatio` (no final "n") is not a typo: Linux truncates
process names at 15 characters.

---

## Configuration

One file, `config.sh`, read by every script through `lib/common.sh`.

`config.sh` is git-ignored and holds secrets; `config.example.sh` is the
tracked template. The installer copies one to the other on first run and never
overwrites an existing `config.sh`.

The UI definitions are four **parallel arrays** — index 0 of each describes
the same UI:

```bash
REC_UI_PROCESSES=("kodi" "emulationstatio" "labwc")
REC_UI_NAMES=("Kodi" "RetroPie" "Desktop")
REC_UI_START=("kodi-standalone &" "emulationstation &" "labwc-pi &")
REC_UI_STOP=("kodi-send --action=\"Quit\"" "pkill emulationstatio" "pkill -x labwc")
```

A parallel-array layout is unusual, but it keeps the file editable by someone
who is not a bash programmer: to drop RetroPie you delete the second entry
from each list. Both `50-ui-rotation/install.sh` and `doctor.sh` check that
the four lengths match, because a mismatch fails at the worst possible moment
— mid-switch, with no UI running.

**These arrays are assigned without `declare -a` on purpose.** `config.sh` is
sourced from inside a function (`rec_load_config`), and `declare` inside a
function creates a *local* variable. With `declare -a`, every script would see
empty arrays and no UI would ever start.

---

## Path resolution

Every script begins:

```bash
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
```

`common.sh` then derives `$REC_ROOT`, `$REC_BIN` and `$REC_ASSETS` from its
own location. Nothing anywhere hardcodes a directory, so:

- the repository can be cloned anywhere,
- scripts work regardless of the current working directory,
- the same checkout works for a user other than `pi`.

`readlink -f` resolves symlinks, so a script symlinked into `/usr/local/bin`
still finds the library.

Config values that need a path use `$REC_BIN`, which is expanded when
`config.sh` is sourced:

```bash
REC_GPIO_BUTTONS=("4:bash $REC_BIN/stop_current_ui.sh")
```

---

## Single-instance locking

`.bashrc` runs on every login, so the background services must tolerate being
started repeatedly. Each one calls:

```bash
rec_single_instance name || exit 0
```

This uses `flock` on a file descriptor. The kernel releases the lock when the
process dies **for any reason**, including `SIGKILL` and a power cut.

The earlier version of this project used "does a lockfile exist?" instead.
That leaves a stale file behind after an unclean shutdown, and the watchdog
then refuses to start on every subsequent boot — a failure that looks exactly
like a broken UI switcher.

---

## Audible feedback

The screen is normally showing a film, so anything that reports state has to
be audible:

- **`signal_action.sh`** plays a short beep the moment a button or remote
  command is accepted. Actions take several seconds to have a visible effect;
  without the beep the button feels broken and gets pressed again.
- **`speech.sh`** speaks full sentences via Google Translate's public TTS
  endpoint — no API key, no account, no local voice data. Offline engines that
  sound acceptable are too slow on a Pi 3B.
- **`nordvpn_monitor.sh`** is the main consumer: it announces every VPN
  connection change.

`speech.sh` checks for connectivity first. Without that check, every message
issued while the network was still coming up produced a page of resolver
errors and no sound.

---

## Reaching the Pi from outside

Two layers, and it is worth being clear about which is which:

**NordVPN Meshnet** (module `70-nordvpn`) gives the Pi a permanent private
address reachable from any other device on your NordVPN account. No router
configuration, no open ports, nothing exposed to the internet. This is the
right answer for SSH and for the Kore remote.

**Port forwarding** (module `75-port-forwarding`) extends that reach to
devices *behind* the Pi. `socat` listens on a port on the Pi and relays to a
LAN address, so an old Android phone running an IP webcam — which cannot run a
VPN client itself — becomes reachable at `meshnet-address:8282`.

**The public web server** (module `80-webserver`) is the separate, genuinely
public option: a No-IP hostname, router port forwarding, Apache and a Let's
Encrypt certificate. It is the only module that exposes the Pi to the open
internet, which is why it asks for confirmation and enables unattended
security upgrades.

There is a trap here worth knowing about: connecting the VPN routes *all*
traffic into the tunnel, including LAN traffic, which kills SSH and every port
forward. `NORDVPN_LAN_SUBNET` is added to the NordVPN allowlist to prevent
this. `doctor.sh` checks that the configured subnet actually matches the Pi's
address, because a mismatch locks you out the moment the VPN connects.

---

## Module system

Each module is `modules/<name>/install.sh`, and every one of them:

- sources `lib/install_helpers.sh` for `apt_install`, `ensure_line`,
  `ensure_block`, `backup_file`, `confirm`;
- is **idempotent** — running it twice changes nothing the second time;
- refuses to run as root, calling `sudo` only for the steps that need it;
- ends by printing the manual steps that cannot be scripted (anything inside a
  running Kodi, mostly).

`ensure_block` maintains marker-delimited blocks in files it does not own:

```
# >>> rpi-entertainment-center >>>
...
# <<< rpi-entertainment-center <<<
```

Re-running replaces the block rather than appending a second copy — which is
what makes editing `config.sh` and re-running the installer safe, and what
lets the repository be moved without leaving a stale `.bashrc` line behind.

`install.sh` records completed modules in `.installed/` so `--list` can show
what is done.

---

## What is deliberately not here

- **No systemd units for the UI.** They run in the wrong session; see above.
- **No central daemon.** Each concern is a small script that can be run,
  read and debugged on its own.
- **No database or state store.** The only runtime state is
  `/tmp/rec-next-ui-index`, and losing it just means the default UI starts.
- **No auto-update.** The system is on the internet; silently pulling and
  running new code is not a property you want in that position.
