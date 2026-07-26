# 00-base — foundation

**Every other module depends on this one. Install it first.**

```bash
./install.sh 00-base
```

---

## What it does

1. Installs the packages every other module assumes: `git`, `curl`, `wget`,
   `unzip`, `python3`, `util-linux` (for `flock`).
2. Installs **NTFS and exFAT support**, so USB drives full of media actually
   mount.
3. Creates **`config.sh`** from `config.example.sh` (mode 600, never
   overwriting an existing one).
4. Makes everything in `bin/` and `modules/` executable.
5. Sets the Pi to **Console Autologin**.
6. Sets the Pi to **wait for the network** before handing over to the login
   shell.
7. Hooks **`autostart.sh`** into `~/.bashrc`.
8. Removes the legacy `bash autostart.sh &` line, if you are upgrading from
   the old layout.

---

## Why console autologin

This is the decision that makes the whole project work.

If the Pi booted straight to the desktop, the desktop would already own the
screen and there would be no opportunity to choose a different UI. Booting to
a plain console means `.bashrc` runs first, `autostart.sh` runs from it, and
the UI watchdog gets to decide what starts.

The installer sets this with:

```bash
sudo raspi-config nonint do_boot_behaviour B2
```

Equivalent to: **`sudo raspi-config` → System Options → Boot / Auto Login →
Console Autologin**.

## Why wait for the network

Otherwise `nordvpn_autostart.sh` races `dhcpcd` on every boot and loses about
half the time, which looks like an intermittently broken VPN.

```bash
sudo raspi-config nonint do_boot_wait 0
```

(`0` means *enable* the wait — the flag reads as "do not skip".)

## Why `.bashrc` and not a systemd service

`autostart.sh` starts UIs, and a UI needs to run **as the logged-in user, in
the session that owns tty1**. A systemd service runs too early and in the
wrong session to start an X server or Kodi.

The trade-off is that `.bashrc` runs for *every* interactive shell, including
every SSH login. `autostart.sh` therefore checks which terminal it is on and
exits immediately unless it is `/dev/tty1`:

```bash
case "$(tty)" in
    /dev/tty1) ;;   # console — proceed
    *) exit 0 ;;    # SSH or anything else — do nothing
esac
```

Without that guard, every SSH login would start a second Kodi on a screen you
cannot see.

The hook itself is written as a marker block, so re-running the installer
updates it rather than adding a second copy:

```bash
# >>> rpi-entertainment-center >>>
[ -f "/home/pi/rpi_entertainment_center/bin/autostart.sh" ] && bash "..." &
# <<< rpi-entertainment-center <<<
```

---

## Configure

```bash
nano config.sh
```

The settings worth reviewing straight away are listed in
[INSTALL.md §7](../INSTALL.md#7-configure); every setting is documented in
[CONFIGURATION.md](CONFIGURATION.md).

---

## Verify

```bash
./bin/doctor.sh base
```

Expected:

```
  PASS  config.sh exists
  PASS  config.sh permissions are 600
  PASS  autostart.sh is hooked into ~/.bashrc
  PASS  Boots to console (multi-user.target)
  PASS  Console autologin is configured
  PASS  All scripts in bin/ are executable
```

Test the autostart chain without rebooting — **from the physical console
only**, since it will try to start a UI:

```bash
REC_FORCE_AUTOSTART=1 bash bin/autostart.sh
```

---

## Troubleshooting

**"Do not run this installer with sudo"**
Correct — run `./install.sh 00-base` as your normal user. It calls `sudo`
itself for the handful of steps that need it. Running the whole thing as root
would leave root-owned files through your home directory.

**Boot behaviour could not be set**
Do it by hand: `sudo raspi-config` → System Options → Boot / Auto Login →
Console Autologin.

**Scripts are not executable**
Usually caused by copying the repository across a filesystem that drops
permission bits (a FAT USB stick, some zip extractors):

```bash
chmod +x bin/*.sh bin/*.py install.sh modules/*/install.sh
```

**`config.sh` was overwritten**
It is not — the installer explicitly skips it if present. If you want to reset
to defaults, delete it first and re-run.

**A USB drive still will not mount**
Check the filesystem type with `sudo blkid`. See
[HARDWARE.md § Storage](HARDWARE.md#storage) for mounting and `/etc/fstab`.
