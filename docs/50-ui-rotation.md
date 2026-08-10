# 50-ui-rotation — one button, three environments

The core of the project. Exactly one UI runs at a time, a watchdog makes sure
one always is, and a single button cycles between them.

```bash
./install.sh 50-ui-rotation
```

**Prerequisites:** `00-base`, plus the UI modules you actually want.

**Install this last** — it checks that the UIs listed in `config.sh` are
really installed, which it can only do once they are.

---

## How it works

```
  ┌──────────────────────────────────────────────────┐
  │  ui_rotate.sh   (watchdog, started at boot)      │
  │                 runs in the FOREGROUND on tty1   │
  │                                                  │
  │  no UI alive?  ──▶  read /tmp/rec-next-ui-index  │
  │                     announce it on the console   │
  │                     run that UI HERE, and wait   │
  │                     for it to exit               │
  └──────────────────────────────────────────────────┘
                          ▲
                          │ reads
                          │
  ┌───────────────────────┴──────────────────────────┐
  │  stop_current_ui.sh  (runs once, on a press)     │
  │                                                  │
  │  1. find the running UI                          │
  │  2. write the NEXT index to the state file       │
  │  3. stop the current UI                          │
  │  4. wait 10s, then SIGKILL if still alive        │
  └──────────────────────────────────────────────────┘
```

Two scripts, deliberately separate: the button handler is short and always
terminates, while the long-running loop has exactly one job.

**The next index is written before anything is killed.** If the switch is
interrupted half-way, the watchdog still finds a valid choice and the TV never
gets stuck on a black screen. It is also how the watchdog tells a deliberate
switch from a UI that failed to start: an index that is not the one that just
exited means somebody pressed the button.

**The watchdog runs in the foreground, on the console.** It starts each UI as
its own child and waits, rather than detaching it and polling `ps`. Two things
follow. The screen shows what is happening — which UI is starting, the command
used, and how long the last one ran — instead of a blank prompt during the
seconds a switch takes. And the trailing `&` in `REC_UI_START` is stripped
before the command runs, so an entry written as `"kodi-standalone &"` still
works and is simply not detached.

**Each UI is attached to the console on all three descriptors**, stdin
included. That last one matters more than it looks:

```bash
# ~/.bashrc
bash .../autostart.sh &
```

Bash points an asynchronous command's stdin at `/dev/null` whenever job control
is off — which it is while startup files are being processed. Every process
below inherits it, so without an explicit `</dev/tty` the UI is started with no
way to read the keyboard.

Nothing looks wrong until something wants to *read* the terminal, and almost
nothing does: Kodi, EmulationStation and the desktop all take their input from
`/dev/input`. **RetroPie's runcommand launch menu is the exception.** It uses
`dialog`, which draws to `/dev/tty` but reads keys from stdin — so the menu
appears normally, and a stdin already at EOF makes `dialog` return instantly
with no selection. The `while true` loop around it redraws the same menu, and
the result looks like a menu that resets to its initial state on every press
and can never be used.

---

## Switching

| Method | How |
|---|---|
| Physical button | GPIO 4 by default — see [60-gpio.md](60-gpio.md) |
| From Kodi | Shell Script Launcher → "Switch UI (next)" |
| From your phone | A KDE Connect command — see [45-kdeconnect.md](45-kdeconnect.md) |
| Over SSH | `bash bin/stop_current_ui.sh` |

Go backwards with `bash bin/stop_current_ui.sh prev`.

Order is the order of the arrays in `config.sh`, wrapping at the end:

```
Kodi → RetroPie → Desktop → Kodi → …
```

---

## Configuration

Four parallel arrays — index 0 of each describes the same UI:

```bash
REC_UI_PROCESSES=("kodi" "emulationstatio" "labwc")
REC_UI_NAMES=("Kodi" "RetroPie" "Desktop")
REC_UI_START=("kodi-standalone &" "emulationstation &" "labwc-pi &")
REC_UI_STOP=("kodi-send --action=\"Quit\"" "pkill emulationstatio" "pkill -x labwc")
REC_UI_DEFAULT_INDEX=0
```

> ### Two of these depend on your system
>
> **Kodi.** The bare `kodi` command is a wrapper that prefers the X11 build and
> cannot start from a console. Use `kodi-standalone` (or `kodi-gbm`) — see
> [10-kodi.md](10-kodi.md#starting-kodi-without-a-desktop).
>
> **The desktop.** `startx`/`Xorg` are correct only under X11. Bookworm and
> later default to **Wayland**, where the command is `labwc` (or `wayfire`):
>
> | | Wayland (default) | X11 |
> |---|---|---|
> | `REC_UI_PROCESSES` | `labwc` | `Xorg` |
> | `REC_UI_START` | `labwc-pi &` | `startx-rpd &` |
> | `REC_UI_STOP` | `pkill -x labwc-pi; pkill -x labwc` | `killall Xorg` |
>
> **Start the session, not the compositor.** `labwc` and `startx` alone give a
> black screen with no panel; `labwc-pi` and `startx-rpd` are the Raspberry Pi
> OS session wrappers that also start the panel and file manager.
>
> Both are installed as standard on Raspberry Pi OS, so what is *present* tells
> you nothing. Check what is *configured*:
>
> ```bash
> raspi-config nonint get_wayland    # 0 = Wayland, 1 = X11
> ```
>
> `./bin/doctor.sh ui` reports the detected server and flags a mismatch in
> either direction.

**They must all have the same number of entries.** The installer and
`doctor.sh` both check this, because a mismatch fails at the worst possible
moment — mid-switch, with no UI running.

### Removing a UI you did not install

Delete the same index from all four arrays. This is not optional: the watchdog
will otherwise try to start something that does not exist, fail, and leave the
screen blank.

Kodi only:

```bash
REC_UI_PROCESSES=("kodi")
REC_UI_NAMES=("Kodi")
REC_UI_START=("kodi-standalone &")
REC_UI_STOP=("kodi-send --action=\"Quit\"")
REC_UI_DEFAULT_INDEX=0
```

With a single entry the switch button becomes a restart button — genuinely
useful on a device with no keyboard.

### Adding your own UI

Anything full-screen works. RetroArch standalone, for instance:

```bash
REC_UI_PROCESSES=("kodi" "retroarch")
REC_UI_NAMES=("Kodi" "RetroArch")
REC_UI_START=("kodi-standalone &" "retroarch &")
REC_UI_STOP=("kodi-send --action=\"Quit\"" "pkill retroarch")
```

Find the exact process name with `ps -A | grep -i <name>` while it runs — and
remember Linux truncates process names at 15 characters.

---

## Why `emulationstatio`

Not a typo. Linux truncates process names at 15 characters, so
`emulationstation` appears as `emulationstatio` in `ps` output. The array must
match what `ps` reports.

---

## Verify

```bash
./bin/doctor.sh ui
```

It checks array lengths, that every configured start command exists, that the
default index is in range, and whether the watchdog is currently running.

Test the whole chain without rebooting — **from the physical console**, since
it starts a UI:

```bash
REC_FORCE_AUTOSTART=1 bash bin/autostart.sh
```

---

## Troubleshooting

### How autostart decides it is on the console

`autostart.sh` must run only on the physical console, or an SSH login would
start a second UI on a screen you cannot see. It determines this from the
**controlling terminal**, reported by `ps`, plus `XDG_VTNR` and an explicit
SSH check.

It deliberately does *not* use `tty`. `tty` reports the terminal of **stdin**,
and `.bashrc` starts autostart with `&` — bash redirects an async command's
stdin to `/dev/null` whenever job control is off, which it is while startup
files run. `tty` therefore prints "not a tty" (localised, so not even reliably
that string) on a perfectly normal console boot. An earlier version checked
`tty` and consequently refused to start on every system, every time.

The decision is logged:

```
Controlling terminal: 'tty1'  XDG_VTNR='1'  SSH=''
On the console - proceeding.
```

```bash
cat ~/.local/state/rec/autostart.log
./bin/doctor.sh autostart
```

---

### No UI starts — black screen after boot

SSH still works, so this is always recoverable.

0. **Check the log first** — it now records why autostart did or did not run:

   ```bash
   cat ~/.local/state/rec/autostart.log
   ```

1. **Is the watchdog running?**

   ```bash
   pgrep -af ui_rotate.sh
   ```

   If not, check the autostart hook:

   ```bash
   grep -A3 "rpi-entertainment-center" ~/.bashrc
   ```

   Missing? Run `./install.sh 00-base`.

2. **Does the configured UI actually exist?**

   ```bash
   ./bin/doctor.sh ui
   ```

   This is the most common cause: RetroPie listed in `config.sh` but never
   installed.

3. **Is the state file corrupt?**

   ```bash
   cat /tmp/rec-next-ui-index
   rm -f /tmp/rec-next-ui-index    # falls back to the default
   ```

4. **Did the Pi boot to the console?**

   ```bash
   systemctl get-default            # want: multi-user.target
   ```

5. **Start a UI by hand** to see the real error — from the console:

   ```bash
   kodi
   ```

### RetroPie's launch menu resets on every button press

You start a ROM, press a button at "Press a button to configure", the menu
appears — and every press puts it back to its initial state, so no option can
be chosen.

**The UI was started without a readable stdin.** `dialog` draws to `/dev/tty`
but reads keys from stdin; at EOF it returns immediately with no selection, and
runcommand's loop redraws the menu. Check what the UI actually got:

```bash
pid=$(pgrep -f emulationstation | head -1)
readlink /proc/$pid/fd/0        # want /dev/tty or /dev/tty1, NOT /dev/null
```

`ui_rotate.sh` attaches `/dev/tty` explicitly when it starts a UI. If you launch
a UI by some other route, do the same:

```bash
emulationstation </dev/tty >/dev/tty 2>&1
```

This is invisible for Kodi, EmulationStation and the desktop, which read
`/dev/input` directly — runcommand's menu is the one thing that needs the
terminal.

### The switch button does nothing

- **Debounce.** Presses within 5 seconds of each other are ignored on purpose.
  Wait and try again.
- **Is the listener running?** `pgrep -af gpio_buttons.py`
- **Run the command directly** to see the error:
  `bash bin/stop_current_ui.sh`
- **Kodi may be refusing to quit.** The script waits 10 seconds then forces
  it, so a switch can take that long.

### Two UIs start at once

The watchdog waits 10 seconds after starting a UI before checking again. If a
UI takes longer than that to appear in `ps`, the watchdog starts a second one.

Increase the sleep in `bin/ui_rotate.sh`, or check why startup is so slow
(usually an SD card at the end of its life).

### A UI is several processes, not one

Kodi launched through `kodi-standalone` runs as **three** processes, all alive
simultaneously:

```
$ ps -A | grep odi
 1053 tty1     00:00:00 kodi-standalone     ← launcher
 1057 tty1     00:00:00 kodi                ← wrapper
 1062 tty1     00:00:32 kodi.bin            ← the actual program
```

This matters twice over:

**Detection.** `REC_UI_PROCESSES="kodi"` matches the wrapper exactly, so the
watchdog sees it. Setting it to `kodi.bin` or `kodi-standalone` also works via
the command-line fallback, but `kodi` is the cleanest.

**Stopping.** `pkill -x kodi` kills *only the wrapper* — `kodi.bin` keeps
running, the screen stays on Kodi, and the switch to the next UI never
completes. The force-kill therefore sweeps the whole family by command line,
excluding the calling script and its ancestors so a script whose own path
contains the name cannot kill itself.

The same applies to `labwc-pi` and to `emulationstation`, which run their real
work under different names.

### Several copies of the same UI are running

The watchdog starts a UI, cannot see it in the process list, concludes nothing
is running, and starts another. Repeat once a second and you get five Kodis.

**Cause: `REC_UI_PROCESSES` does not match what actually runs.** The name a UI
appears under often differs from the command that starts it — `kodi-standalone`
is a script that `exec`s `kodi.bin`, so once it has handed over, the original
name matches nothing.

```bash
ps -A | grep -i kodi          # what is it actually called?
pgrep -a kodi                 # full command lines
```

Put the name from the left-hand column of `ps -A` into `REC_UI_PROCESSES`.

The watchdog now guards against this in three ways:

- it looks for **both** the configured process name and the basename of the
  start command, so either matching is enough;
- it refuses to start a UI that already appears to be running;
- after three failed starts it pauses for five minutes rather than launching
  another copy every cycle.

To clean up existing duplicates:

```bash
pkill -f ui_rotate.sh     # stop the watchdog first, or it restarts them
pkill -f kodi
```

`autostart.sh` restarts the watchdog at the next console login, or reboot.

### A UI is installed but reported "not found"

`rec_has` searches `PATH`, `/sbin`, `/usr/sbin` and RetroPie's directories
under `/opt/retropie`. RetroPie does not always put `emulationstation` on
`PATH`, so a working install can still fail this check.

Both `doctor.sh` and the watchdog now look outside `PATH` before saying
anything is missing, and report where they found it:

```
Desktop -> 'emulationstation' is not on PATH, but exists at
           /opt/retropie/supplementary/emulationstation/emulationstation
```

Use that absolute path in `REC_UI_START`:

```bash
REC_UI_START=(... "/opt/retropie/supplementary/emulationstation/emulationstation &" ...)
```

### The switcher keeps cycling on its own

A UI is starting and immediately exiting. The watchdog sees "nothing running",
starts the next, and so on. Find the culprit:

```bash
kodi ; echo "exit code: $?"
```

Run each configured start command by hand from the console until one fails.

### Everything restarts when I SSH in

The autostart guard is missing or has been edited. `autostart.sh` should exit
unless it is on `/dev/tty1`. Re-run `./install.sh 00-base`.

### A stale lock stops the watchdog

The lock is held with `flock`, which the kernel releases when the process
dies — including after a power cut. If you suspect a stale lock anyway:

```bash
ls -l /run/lock/rec-*.lock
pgrep -af ui_rotate.sh
```

An unlocked file left on disk is harmless; only a live process holds the lock.
