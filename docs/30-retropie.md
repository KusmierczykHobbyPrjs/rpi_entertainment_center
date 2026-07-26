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
