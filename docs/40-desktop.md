# 40-desktop — the desktop, as the third UI

The third UI. Kodi covers media and RetroPie covers games, but some things
need a real browser: web-only video players, webmail, a bank, a shopping site.

```bash
./install.sh 40-desktop
```

**Prerequisites:** `00-base`.

---

## It does not install a desktop

> **On Bookworm and later, Raspberry Pi OS already ships a desktop** (the
> `rpd-*` packages). Installing another one makes apt **remove** it:
>
> ```
> The following packages will be REMOVED:
>   rpd-common rpd-wayland-core rpd-x-core
> ```
>
> An earlier version of this module installed `lxde-core` unconditionally and
> did exactly that. It now detects the existing desktop and leaves it alone.

What it actually does:

1. Confirms a desktop is present (and stops with instructions if not).
2. Detects **Wayland or X11**, which changes everything downstream.
3. Installs only the missing pieces — `wlr-randr` under Wayland,
   `x11-xserver-utils` and `xinit` under X11 — plus Chromium.
4. Hooks `desktop_set_resolution.sh` into the right session autostart.
5. Prints the exact `REC_UI_*` values your session needs.

**This does not change the boot target.** The Pi still boots to a console; the
desktop is started on demand by the UI switcher.

---

## Wayland changes the UI entries

Bookworm and later default to Wayland (labwc on Trixie). That matters because
the defaults in `config.example.sh` assume X11:

| | X11 | Wayland |
|---|---|---|
| `REC_UI_PROCESSES` | `Xorg` | `labwc` (or `wayfire`) |
| `REC_UI_START` | `startx &` | `labwc &` |
| `REC_UI_STOP` | `killall Xorg` | `pkill -x labwc` |
| Resolution tool | `xrandr` | `wlr-randr` |

**If you are on Wayland and leave the X11 defaults, the watchdog tries to
start an X server that is not there and you get a black screen.** The
installer prints the correct values for your system; `./bin/doctor.sh ui`
checks them.

Which are you on?

```bash
echo "$XDG_SESSION_TYPE"     # from inside a desktop session
```

---

## Why the resolution is pinned

The desktop otherwise picks the highest mode the TV advertises — typically
1080p. A Pi 3B cannot play video in a browser at that size; you get a
slideshow.

`desktop_set_resolution.sh` runs at session start and pins the desktop to
something the Pi can actually drive. Kodi and RetroPie set their own modes, so
they are unaffected — which is why this is done per session rather than
globally in `/boot/firmware/config.txt`.

Configure it in `config.sh`:

```bash
export REC_DESKTOP_OUTPUT="HDMI-1"
export REC_DESKTOP_MODE="1360x768"
export REC_DESKTOP_RATE="60"
```

Find what your TV supports — **from inside a running desktop session**, not
over a plain SSH login:

```bash
wlr-randr                 # Wayland (Bookworm and later)
DISPLAY=:0 xrandr         # X11
```

> `xrandr` printing **`Can't open display`** means one of two things: you ran
> it over SSH with no session, or you are on Wayland, where `xrandr` does not
> work at all. Use `wlr-randr` in that case.

Output names vary between drivers (`HDMI-1` vs `HDMI-A-1`). If the configured
name is not found, the script falls back to the first connected output and
prints the name to set.

---

## Using the desktop

**Getting there:** press the switch-UI button, or use "Switch UI" in the Kodi
menu, until the desktop comes up. Over SSH:

```bash
bash bin/stop_current_ui.sh
```

**Leaving:** the same button. Logging out from the desktop menu has the same
effect — the watchdog sees the session end and starts the next UI — but the
button is the intended route.

**Controlling it:** install module `45-kdeconnect` and use your phone as a
touchpad and keyboard. See [45-kdeconnect.md](45-kdeconnect.md).

---

## Opening a URL from your phone

The main reason this UI exists. With `45-kdeconnect` installed:

1. Copy a URL on your phone.
2. KDE Connect → **Send clipboard**.
3. KDE Connect → Run command → **Open clipboard URL**.

`clipboard2chromium.sh` reads the clipboard, checks it really is an `http(s)`
URL, closes any existing Chromium, and opens it full-screen.

The check matters: without it a clipboard containing arbitrary text would be
handed to the browser as a search or a local file path.

---

## Verify

```bash
./bin/doctor.sh ui
```

Start the desktop by hand from the **physical console** — using whichever
your session is:

```bash
labwc          # Wayland (Bookworm and later)
startx         # X11
```

Test the resolution script from inside a running session:

```bash
bash bin/desktop_set_resolution.sh
```

---

## Troubleshooting

**`xrandr` says "Can't open display"**

Either you ran it over SSH with no desktop session, or you are on Wayland.
Check with `echo $XDG_SESSION_TYPE`; if it says `wayland`, use `wlr-randr`.

**`startx` fails, or does nothing**

On Wayland there is no `startx` — the compositor is `labwc` or `wayfire`.
Check what your session actually uses before assuming X11.

Under X11, `startx` needs a real console: run it from the physical console,
or let the UI switcher start it.

**`startx` fails on the console with a permissions error**

X started by a non-root user needs to own the virtual terminal. Module
`30-retropie` adds you to the `tty` group, which covers this; if you skipped
that module:

```bash
sudo usermod -a -G tty $USER      # then log out and back in
sudo chmod 0744 /dev/tty0
```

**The screen is the wrong size, or has black bars**

- List available modes: `wlr-randr` (Wayland) or `DISPLAY=:0 xrandr` (X11).
- Set `REC_DESKTOP_MODE` to one of them.
- If your TV overscans, add `disable_overscan=1` to
  `/boot/firmware/config.txt` — note the path changed in Bookworm.

**"Mode ... was rejected"**

The script prints the modes the output actually supports. Pick one of those.

**Chromium is unusably slow**

- Lower `REC_DESKTOP_MODE` — 1280x720 or 1024x768 helps a great deal.
- Close other tabs; a Pi 3B has 1 GB of RAM shared with the GPU.
- Do **not** bother setting `gpu_mem` — it is ignored on Bookworm and later,
  where video memory is allocated dynamically. See
  [HARDWARE.md](HARDWARE.md#the-boot-config-file).
- Some sites are simply beyond a Pi 3B. Where a Kodi add-on exists for the
  same service, use it instead — it will be far smoother.

**Chromium reopens old tabs, or shows a "didn't shut down correctly" bar**

`chromium_kill.sh` clears the session data and resets the exit flag to prevent
exactly this. If it persists, run it manually:

```bash
bash bin/chromium_kill.sh
```

**The desktop starts but the resolution script did not run**

Where the autostart entry lives depends on your session:

```bash
cat ~/.config/labwc/autostart                        # Wayland / labwc
grep -A2 rpi-entertainment-center \
    /etc/xdg/lxsession/LXDE-pi/autostart             # X11 / LXDE
```

Re-run `./install.sh 40-desktop`, which writes to the right one for you.

**No sound in the browser**

The desktop and Kodi use different audio paths. Bookworm and later use
**PipeWire** (not PulseAudio); check the output device in the taskbar volume
applet, and confirm the right output is selected in `raspi-config` → System
Options → Audio.
