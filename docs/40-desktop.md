# 40-desktop — the LXDE desktop

The third UI. Kodi covers media and RetroPie covers games, but some things
need a real browser: web-only video players, webmail, a bank, a shopping site.

```bash
./install.sh 40-desktop
```

**Prerequisites:** `00-base`.

---

## What it installs

| Package | Why |
|---|---|
| `lxde-core`, `lxde-common`, `openbox-lxde-session` | The desktop environment. Lightweight enough for a Pi 3B. |
| `x11-xserver-utils` | Provides `xrandr`, used to set the resolution. |
| `xinit` | Provides `startx`, which is how the UI switcher launches the desktop. |
| `chromium-browser` | The browser. |

It also adds `desktop_set_resolution.sh` to the LXDE session autostart.

**This does not change the boot target.** The Pi still boots to a console; the
desktop is started on demand by the UI switcher.

---

## Why the resolution is pinned

LXDE otherwise picks the highest mode the TV advertises — typically 1080p. A
Pi 3B cannot play video in a browser at that size; you get a slideshow.

`desktop_set_resolution.sh` runs at session start and pins the desktop to
something the Pi can actually drive. Kodi and RetroPie set their own modes, so
they are unaffected — which is precisely why this is done with `xrandr` per
session rather than globally in `/boot/config.txt`.

Configure it in `config.sh`:

```bash
export REC_DESKTOP_OUTPUT="HDMI-1"
export REC_DESKTOP_MODE="1360x768"
export REC_DESKTOP_RATE="60"
```

Find what your TV supports:

```bash
DISPLAY=:0 xrandr
```

Output names vary between display drivers (`HDMI-1` vs `HDMI-A-1`). If the
configured name is not found, the script falls back to the first connected
output and prints the name to set.

---

## Using the desktop

**Getting there:** press the switch-UI button, or use "Switch UI" in the Kodi
menu, until the desktop comes up. Over SSH:

```bash
bash bin/stop_current_ui.sh
```

**Leaving:** the same button. Do not log out from the LXDE menu — the watchdog
sees `Xorg` disappear and simply starts the next UI, which is the same
outcome, but the button is the intended route.

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

Start the desktop by hand from the **physical console**:

```bash
startx
```

Test the resolution script inside a running session:

```bash
DISPLAY=:0 bash bin/desktop_set_resolution.sh
```

---

## Troubleshooting

**`startx` fails over SSH**

Expected. X needs a real console. Run it from the physical console, or let the
UI switcher start it.

**`startx` fails on the console with a permissions error**

X started by a non-root user needs to own the virtual terminal. Module
`30-retropie` adds you to the `tty` group, which covers this; if you skipped
that module:

```bash
sudo usermod -a -G tty $USER      # then log out and back in
sudo chmod 0744 /dev/tty0
```

**The screen is the wrong size, or has black bars**

- List available modes: `DISPLAY=:0 xrandr`
- Set `REC_DESKTOP_MODE` to one of them.
- If your TV overscans, add to `/boot/config.txt`:

  ```
  disable_overscan=1
  ```

**"Mode ... was rejected"**

The script prints the modes the output actually supports. Pick one of those.

**Chromium is unusably slow**

- Lower `REC_DESKTOP_MODE` — 1280x720 or 1024x768 helps a great deal.
- Close other tabs; a Pi 3B has 1 GB of RAM shared with the GPU.
- Raise the GPU memory split to 128 MB in `raspi-config`.
- Some sites are simply beyond a Pi 3B. Where a Kodi add-on exists for the
  same service, use it instead — it will be far smoother.

**Chromium reopens old tabs, or shows a "didn't shut down correctly" bar**

`chromium_kill.sh` clears the session data and resets the exit flag to prevent
exactly this. If it persists, run it manually:

```bash
bash bin/chromium_kill.sh
```

**The desktop starts but the resolution script did not run**

Check the LXDE autostart file:

```bash
grep -A2 "rpi-entertainment-center" /etc/xdg/lxsession/LXDE-pi/autostart
```

The directory name follows the session name and is `LXDE` rather than
`LXDE-pi` on plain Debian. Re-run `./install.sh 40-desktop` after correcting.

**No sound in the browser**

The desktop uses PulseAudio while Kodi uses ALSA directly. Check the output
device in the LXDE volume applet, and confirm HDMI is selected in
`raspi-config` → System Options → Audio.
