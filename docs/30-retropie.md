# 30-retropie — retro gaming

RetroPie is EmulationStation (a full-screen game launcher) plus a large set of
emulators. It is the second UI in the rotation.

```bash
./install.sh 30-retropie
```

**Prerequisites:** `00-base`.
**Time:** 45–120 minutes on a Pi 3B. It compiles emulators from source.

---

## What it does

1. Installs the build dependencies.
2. Clones [RetroPie-Setup](https://github.com/RetroPie/RetroPie-Setup) to
   `~/RetroPie-Setup`.
3. Adds you to the `tty`, `input`, `video` and `audio` groups.
4. Opens RetroPie's own setup menu.

RetroPie has no Debian package — it is installed by its own script, which is
also the supported way to choose which emulators you want. This module gets
you to that menu with the surrounding setup already done.

### Why the group memberships

EmulationStation runs on tty1 without X, and needs to own the terminal, read
the gamepad, write to the framebuffer and open the sound device. Without `tty`
in particular it exits immediately with a permissions error that gives no hint
about the cause.

**These take effect at your next login.** Log out and back in, or reboot.

---

## Choosing what to install

In RetroPie's menu:

- **Basic install** — core packages plus the common emulators. What most
  people want. 45–90 minutes on a Pi 3B.
- **Manage packages** — pick individual emulators. Use this if you only care
  about one or two systems and want to save an hour.

Re-open the menu any time:

```bash
sudo ~/RetroPie-Setup/retropie_setup.sh
```

---

## Adding ROMs

ROMs go in `~/RetroPie/roms/<system>/`:

```
~/RetroPie/roms/nes/
~/RetroPie/roms/snes/
~/RetroPie/roms/megadrive/
~/RetroPie/roms/psx/
~/RetroPie/roms/atari2600/
```

Copy them over the network:

```bash
scp game.zip pi@rpi:~/RetroPie/roms/snes/
```

Or install Samba from the RetroPie setup menu (Configuration → Samba ROM
shares) and drag files to `\\rpi\roms`.

EmulationStation only shows systems that have at least one ROM, so an empty
menu after installation is expected, not a fault.

Some systems (PlayStation, and several arcade boards) also need BIOS files in
`~/RetroPie/BIOS/`. RetroPie's own documentation lists which.

> This project does not distribute ROMs or BIOS files. Use your own dumps or
> the freely-licensed homebrew that many systems have.

---

## Controllers

Most USB gamepads work immediately. Start EmulationStation once and it walks
you through the button mapping:

```bash
emulationstation
```

Re-run the mapping later from EmulationStation's own menu (press Start →
Configure Input).

Kodi uses the same pad through `kodi-peripheral-joystick`, so one controller
covers both.

### A pad that is not detected

Some generic controllers need their vendor and product IDs adding by hand.
Find them:

```bash
lsusb
cat /proc/bus/input/devices | grep -A5 -i joystick
```

Then edit the autoconfig file for your pad in
`/opt/retropie/configs/all/retroarch/autoconfig/` and add:

```
input_vendor_id = "121"
input_product_id = "6"
```

(Example values from a DragonRise generic pad — use your own.)

### EmulationStation asks me to configure a pad I already configured

Typically right after restoring a backup onto a fresh install. The mapping is
in `es_input.cfg`, and EmulationStation genuinely cannot tell it belongs to the
pad you have plugged in.

ES identifies a controller by its **SDL GUID**, which is not a serial number
but a hash of what the pad reports:

```
0300 457e 7900 0000 0600 0000 1001 0000
 |    |    |         |         |
 bus  |    vendor    product   version
      CRC-16 of the device NAME
```

That third field is the problem. SDL changed whether it collapses the runs of
whitespace in the kernel's device name before hashing it, so the same physical
pad gets a different GUID on a newer image:

| | name that gets hashed | CRC |
|---|---|---|
| older SDL | `DragonRise Inc. Generic USB Joystick` | `2061` |
| newer SDL | `DragonRise Inc.   Generic   USB  Joystick  ` | `457e` |

Vendor, product and version are identical — only the name hash moved. Restore
therefore works perfectly and the controller still does not bind.

Relink it rather than mapping every button again:

```bash
python3 bin/controller_relink.py            # show what would change
python3 bin/controller_relink.py --apply    # write it (backs up first)
```

It computes the GUID your pad has on *this* system, finds entries describing
the same physical device (same bus, vendor, product and version) and rewrites
only the GUID field.

**RetroArch is not affected** by any of this — its autoconfig files match on
name plus `input_vendor_id` and `input_product_id`, none of which change
between versions. This is an EmulationStation-only failure, which is why games
can play fine while the ES menu itself refuses the pad.

### I cannot exit a game — Select+Start does nothing

Almost always because the game is running under a **standalone** emulator
rather than a libretro one.

Select+Start is a *RetroArch* feature. Every `lr-*` emulator runs inside
RetroArch and gets it; standalone emulators — `mupen64plus-gles2rice`, PPSSPP,
Amiberry — do not use RetroArch at all, so the hotkey does not exist there. You
usually arrive at one by choosing it from runcommand's launch menu because the
default did not work for a particular ROM.

**Immediate escape:** `ESC` on a keyboard quits standalone mupen64plus. Failing
that, from another machine:

```bash
ssh pi@rpi 'kill $(pgrep -x mupen64plus)'
```

Use the PID. `pkill -f mupen64plus` matches *its own* command line and kills
your SSH session instead.

**The fix:**

```bash
python3 bin/controller_hotkeys.py            # show what would change
python3 bin/controller_hotkeys.py --apply
```

RetroPie already tries to do this — its mupen64plus scriptmodule copies your
RetroArch hotkeys into `mupen64plus.cfg` — but it finds your autoconfig by
matching the device *name*:

```
kernel  /sys/class/input/js0/device/name : DragonRise Inc.   Generic   USB  Joystick
autoconfig  input_device                 : DragonRise Inc. Generic USB Joystick
```

For any pad whose name contains runs of whitespace those never match, the
lookup silently yields nothing, and you get `Joy Mapping Stop = ""`. The same
quirk breaks [controller mappings after a
restore](#emulationstation-asks-me-to-configure-a-pad-i-already-configured).

`controller_hotkeys.py` matches on **vendor and product ID** instead, which
whitespace cannot affect, and writes the binding RetroPie would have written:

```
Joy Mapping Stop = "J0B8/B9,J1B8/B9"
```

That is RetroPie's own format — `J<pad>B<hotkey>/B<action>` — covering every
connected pad, and it handles buttons, hats and axes.

**What it does not cover.** The controller side is general; the emulator side
cannot be, because standalone emulators share no common input format. It writes
`mupen64plus.cfg` for every system that has one. Anything else it finds — PPSSPP,
Amiberry, ScummVM — is listed in the output rather than silently skipped, so
you know what still needs doing by hand.

It also reports a trap worth knowing about: if the exit button and the hotkey
button are the **same**, the combo collapses and a single press quits mid-game.
That happens easily by pressing Select and Start in the wrong order when
configuring the pad in EmulationStation.

---

## Performance on a Pi 3B

A Pi 3B's VideoCore IV draws the EmulationStation UI at whatever the HDMI mode
is. At 1920x1080 that is 2.07M pixels per frame for a menu, and it feels
sluggish long before any game starts.

Check first that it is really the resolution and not something dumber:

```bash
vcgencmd get_throttled     # 0x0 means it has never throttled
vcgencmd measure_temp      # sustained >80'C throttles the CPU
df -h /                    # a full card slows everything
```

If those are clean, lower the resolution ES runs at. It takes a flag:

```bash
emulationstation --resolution 1360 768
```

Put it in `REC_UI_START` in `config.sh` so the UI watchdog uses it:

```bash
REC_UI_START=("kodi-standalone &" "emulationstation --resolution 1360 768 &" "labwc-pi &")
```

Kodi and the desktop keep their own resolution, so video playback stays at
1080p — only the emulator UI drops.

**Use a mode your TV actually offers**, or SDL falls back and nothing improves:

```bash
cat /sys/class/drm/card*/card*-HDMI-A-1/modes
```

Many TVs do not list `1280x720` at all. `1360x768` is the usual 16:9
alternative, and still roughly halves the pixels.

For the games themselves, RetroArch has its own setting in
`/opt/retropie/configs/all/retroarch.cfg`:

```
video_fullscreen_x = "1360"
video_fullscreen_y = "768"
```

### N64 specifically

N64 is the hardest system a Pi 3B is asked to run, and RetroPie installs two
cores for it. The default, `lr-mupen64plus-next`, is the more accurate and the
more demanding; `lr-mupen64plus` is the one to prefer on a Pi 3.

```bash
# /opt/retropie/configs/n64/emulators.cfg
default = "lr-mupen64plus"
```

The GLideN64 framebuffer options cost the most. In
`/opt/retropie/configs/all/retroarch-core-options.cfg`:

```
mupen64plus-next-EnableCopyColorToRDRAM = "Off"      # was "Sync"
mupen64plus-next-EnableCopyDepthToRDRAM = "Off"      # was "Software"
mupen64plus-next-EnableCopyAuxToRDRAM   = "False"
```

A few games lose minor effects (motion blur, some transitions) and run
markedly better.

Internal render resolution is separate from the screen mode and is what makes
N64 look soft:

```
mupen64plus-next-43screensize = "640x480"     # the default
```

Raising it sharpens the image and costs framerate directly — on a Pi 3B,
640x480 is usually the right trade. Change one thing at a time and test with a
demanding game (Conker, DK64) rather than a simple one.

---

## How it fits the UI rotation

EmulationStation appears in `config.sh` as:

```bash
REC_UI_PROCESSES=(... "emulationstatio" ...)
REC_UI_NAMES=(...     "RetroPie"        ...)
REC_UI_START=(...     "emulationstation &" ...)
REC_UI_STOP=(...      "pkill emulationstatio" ...)
```

**`emulationstatio` is not a typo.** Linux truncates process names at 15
characters, so that is what `ps` reports.

Stopping it with `pkill` rather than a clean quit is deliberate:
EmulationStation's own exit paths vary between versions and some of them
restart it. See
[the RetroPie forum discussion](https://retropie.org.uk/forum/topic/22266/how-to-cleanly-stop-emulationstation-from-the-command-line/3)
for the background.

If you did not install RetroPie, **remove its entry from all four arrays** in
`config.sh` — otherwise the watchdog tries to start something that does not
exist and leaves the screen blank. `./bin/doctor.sh ui` catches this.

---

## Verify

```bash
./bin/doctor.sh ui
ls /opt/retropie/
emulationstation --help
```

Screenshot of the running system: [`photos/retropie/`](../photos/retropie/).

---

## Troubleshooting

**EmulationStation exits immediately**

Almost always the `tty` group. Check and re-login:

```bash
id -nG | grep tty
sudo usermod -a -G tty $USER
```

You can also see the real error by running it from the console (not SSH).

**"No games found"**

- ROMs must be in the right per-system directory.
- The file extension must be one the emulator expects (`.zip`, `.nes`,
  `.sfc`, …).
- Restart EmulationStation after adding files — it scans at startup.

**A game runs but the controller does nothing**

Configure the input from EmulationStation's menu, and check the emulator's own
RetroArch config in `/opt/retropie/configs/<system>/`.

**Games run slowly**

- A Pi 3B manages up to roughly the PlayStation era. N64, Dreamcast and PSP
  are beyond it.
- Check throttling: `vcgencmd get_throttled` should print `0x0`.
- Check temperature: `./bin/pi_temp.sh`.
- In RetroArch, try a lighter core for the same system.

**No sound in games**

```bash
sudo raspi-config    # System Options -> Audio -> HDMI
alsamixer            # check nothing is muted
```

**The install failed part-way**

RetroPie's setup is resumable. Re-open the menu and retry the failed package:

```bash
sudo ~/RetroPie-Setup/retropie_setup.sh
```

Its log is at `/home/pi/RetroPie-Setup/logs/`.
