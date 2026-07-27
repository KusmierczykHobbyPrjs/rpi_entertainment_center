# Troubleshooting

Organised by **symptom**, because that is what you have when something breaks.

**Start here:**

```bash
./bin/doctor.sh
```

It checks every module and prints the exact command to fix each problem. Most
of what follows is only needed when `doctor.sh` comes back clean and something
is still wrong.

---

## Contents

- [Nothing appears on the TV](#nothing-appears-on-the-tv)
- [The switch-UI button does nothing](#the-switch-ui-button-does-nothing)
- [SSH drops when the VPN connects](#ssh-drops-when-the-vpn-connects)
- [No sound](#no-sound)
- [Video stutters](#video-stutters)
- [A GPIO button does nothing](#a-gpio-button-does-nothing)
- [Kore cannot find Kodi](#kore-cannot-find-kodi)
- [An add-on installs but plays nothing](#an-add-on-installs-but-plays-nothing)
- [The Pi is slow or unstable in general](#the-pi-is-slow-or-unstable-in-general)
- [Everything restarts when I SSH in](#everything-restarts-when-i-ssh-in)
- [Scripts fail with "command not found"](#scripts-fail-with-command-not-found)
- [Where the logs are](#where-the-logs-are)
- [Starting over](#starting-over)

---

## Nothing starts at boot — no Kodi, no services

The most common cause is that **the Pi booted into the desktop instead of the
console**, so `~/.bashrc` never ran on tty1 and `autostart.sh` never executed.
A Raspberry Pi OS "with desktop" image does this by default.

**First, look at the log.** `autostart.sh` records every run:

```bash
cat ~/.local/state/rec/autostart.log
./bin/doctor.sh autostart
```

| What the log says | Meaning |
|---|---|
| *(file does not exist)* | It has never run at all — the boot target is wrong, see below |
| `Not the console` only | It ran, but never on a console — see below |
| `On the console - proceeding` | It ran; the problem is further down (a UI failing to start) |

The log records the controlling terminal it detected:

```
Controlling terminal: 'tty1'  XDG_VTNR='1'  SSH=''
```

`tty1` (or any `ttyN`) with no SSH marker means console. `pts/N`, or an SSH
marker, means a remote login and autostart correctly declines.

> **Historical note.** Versions before this used `tty` to make that decision,
> which reports the terminal of *stdin*. `.bashrc` starts autostart with `&`,
> and bash redirects an async command's stdin to `/dev/null` while job control
> is off — which it is during startup files. `tty` therefore printed "not a
> tty" (localised, so not even reliably that string) on a perfectly normal
> console boot, and autostart refused to run every single time. If your log is
> full of `Not the console (tty='not a tty')` or its translation, you are on
> that version: `git pull`.

**Check the boot target:**

```bash
systemctl get-default                  # want: multi-user.target
ls /etc/systemd/system/getty@tty1.service.d/autologin.conf
```

If either is wrong:

```bash
sudo raspi-config
  → System Options → Boot / Auto Login → Console Autologin
sudo reboot
```

**Check no display manager is grabbing the screen.** This produces exactly the
same symptom even with a correct boot target:

```bash
for dm in lightdm gdm3 sddm greetd; do systemctl is-enabled $dm 2>/dev/null; done
sudo systemctl disable lightdm         # whichever is enabled
```

**If it ran on the console but no UI appeared**, the configured UI cannot
start. The usual cause on Bookworm and later is Wayland: `config.example.sh`
defaults to `startx` / `Xorg`, which do not exist on a Wayland session.

```bash
echo "$XDG_SESSION_TYPE"       # from a desktop session
./bin/doctor.sh ui
```

See [40-desktop.md](40-desktop.md#wayland-changes-the-ui-entries) for the
`REC_UI_*` values Wayland needs.

**Test the whole chain without rebooting**, from the physical console:

```bash
REC_FORCE_AUTOSTART=1 bash bin/autostart.sh
```

---

## Nothing appears on the TV

Black screen after boot. **SSH still works, so this is always recoverable.**

Work through these in order:

**1. Did the Pi boot to a console?**

```bash
systemctl get-default          # want: multi-user.target
```

Wrong? `sudo raspi-config nonint do_boot_behaviour B2`

**2. Is the watchdog running?**

```bash
pgrep -af ui_rotate.sh
```

Not running? Check the autostart hook exists:

```bash
grep -A3 "rpi-entertainment-center" ~/.bashrc
```

Missing? `./install.sh 00-base`

**3. Do the configured UIs actually exist?**

```bash
./bin/doctor.sh ui
```

**This is the most common cause**: `config.sh` lists RetroPie or the Desktop,
but that module was never installed. The watchdog tries to start something
that is not there, fails, and the screen stays black.

Fix by installing it, or by removing that UI from **all four** arrays in
`config.sh`.

**4. Is the state file corrupt?**

```bash
cat /tmp/rec-next-ui-index
rm -f /tmp/rec-next-ui-index      # falls back to the default UI
```

**5. Start a UI by hand** — from the physical console, not SSH:

```bash
kodi
```

The error it prints is the real answer.

**6. Is it the TV rather than the Pi?**

Try a different HDMI input and cable. If the Pi is connected to a TV that was
off at boot, it may have detected no display at all — reboot with the TV on.

---

## The switch-UI button does nothing

**Debounce.** Presses within 5 seconds of each other are ignored deliberately.
Wait, then press once.

**Is the listener running?**

```bash
pgrep -af gpio_buttons.py
```

**Run the command directly** to see the real error:

```bash
bash bin/stop_current_ui.sh
```

**Kodi may be refusing to quit.** The script sends `Quit`, waits 10 seconds,
then forces it — so a switch can legitimately take that long. If it happens
every time, check `~/.kodi/temp/kodi.log`.

**Only one UI configured?** Then the button restarts that UI rather than
switching. That is correct behaviour.

---

## SSH drops when the VPN connects

**The classic failure.** Connecting the VPN routes all traffic into the
tunnel, including traffic to your own LAN, unless the subnet is allowlisted.

Recover from the Pi's physical console:

```bash
nordvpn disconnect
```

Then fix it properly:

```bash
ip route | grep -v default | grep "$(hostname -I | awk '{print $1}' | cut -d. -f1-3)"
nano config.sh                    # set NORDVPN_LAN_SUBNET to match
./install.sh 70-nordvpn
```

Verify:

```bash
nordvpn settings | grep -i allow
./bin/doctor.sh vpn
```

`doctor.sh` cross-checks the configured subnet against the Pi's real address
specifically to catch this before it bites.

---

## No sound

**Is there a sound card at all?**

```bash
aplay -l
```

Nothing listed usually means audio is routed to HDMI with nothing connected.

**Force the output:**

```bash
sudo raspi-config     # System Options -> Audio -> HDMI, or Headphones
```

**Check the mixer.** In `alsamixer`, `MM` under a channel means muted — press
`M`:

```bash
alsamixer
```

**Test independently of this project:**

```bash
speaker-test -t sine -f 440 -c 2 -l 1
```

**Beeps work but speech does not?** Speech needs the internet; the beep is a
local file.

```bash
ping -c1 1.1.1.1
bash bin/speech.sh "test"
```

**Sound works over SSH but not from a button?**

```bash
id -nG | grep audio
sudo usermod -a -G audio $USER    # then log out and back in
```

More detail: [90-speech.md](90-speech.md).

---

## Sound is too quiet, even at maximum volume

Two things are going on, and only one of them is fixable in software.

### Volume is a chain, not a single control

```
Kodi volume  ×  PipeWire stream  ×  PipeWire sink  ×  ALSA PCM  =  output
```

Every stage multiplies. Kodi at 100% into a sink at 40% gives you 40%. Setting
one to maximum achieves very little on its own.

```bash
./bin/doctor.sh audio          # reports each stage
```

### Use the right tool, or it reverts at every reboot

**On Bookworm and later, WirePlumber owns the hardware mixer.** It stores its
own per-device volume and re-applies it at every startup — *after* ALSA has
restored anything you saved. So:

```bash
# CORRECT on PipeWire - WirePlumber persists this itself
wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%
wpctl set-mute   @DEFAULT_AUDIO_SINK@ 0

# DOES NOT SURVIVE A REBOOT on PipeWire - WirePlumber overwrites it
amixer sset PCM 100%
sudo alsactl store
```

If `alsamixer` shows the level dropping back after every reboot, this is why:
you set it with the wrong tool, and the thing that runs last wins.

There is nothing extra to run — WirePlumber saves the `wpctl` value under
`~/.local/state/wireplumber/` by itself.

**Only on systems without PipeWire** is the `amixer` + `alsactl store` pair
correct, and there it also needs `alsa-restore.service` enabled to reapply the
saved state at boot:

```bash
systemctl is-enabled alsa-restore
```

PipeWire accepts values above 100%, which genuinely helps on a Pi:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 150%
```

That is real amplification, so loud passages may clip. Try 120–150% and back
off if it distorts.

### Improve the analogue output itself

In `/boot/firmware/config.txt`:

```
audio_pwm_mode=2
```

This selects the better PWM modulation for the 3.5 mm jack — a clear
signal-to-noise improvement. Reboot to apply.

### The part software cannot fix

**The Pi's 3.5 mm jack is not a DAC.** It is pulse-width modulation from two
GPIO pins through a passive filter. Output sits well below line level and
carries audible noise, and on a Pi 3B it is worse than on a Pi 4.

If it is still too quiet with everything maxed, you are at the hardware limit.
In increasing order of cost:

| Fix | Notes |
|---|---|
| **Powered speakers with their own gain** | Passive speakers cannot be driven by this output at all |
| **HDMI audio instead** | If your TV or AV receiver handles sound, this bypasses the jack entirely and sounds far better — `sudo raspi-config` → System Options → Audio → HDMI |
| **USB DAC** | £10–20, appears as a normal sink, transforms both level and noise floor |
| **I²S DAC HAT** | Best quality, uses the GPIO header |

**HDMI is the one to try first** — it costs nothing and is a large improvement,
provided something downstream can take the audio.

### Kodi-specific things that quieten playback

- **Settings → System → Audio → Volume amplification** — per-item, resets
  between videos, but worth checking during playback.
- **ReplayGain** (Settings → Player → Music) applies attenuation to tagged
  files. If music is quiet but video is not, look here.
- Try pointing Kodi at the ALSA device directly rather than `Default
  (PipeWire)` — one fewer resampling stage, and occasionally louder.

---

## Video stutters

In order of how often each is the cause:

**1. Power supply.** Under-voltage throttles the Pi silently.

```bash
vcgencmd get_throttled       # want 0x0
```

Anything else means under-voltage or overheating has occurred. Use a 2.5 A+
supply — phone chargers frequently under-deliver.

**2. GPU memory.**

```bash
sudo raspi-config     # Performance Options -> GPU Memory -> 128
```

The default 64 MB is not enough for 1080p on a Pi 3B.

**3. Temperature.**

```bash
./bin/pi_temp.sh
```

Above 80 °C the Pi throttles. Improve ventilation or add a heatsink.

**4. Network.** Wired Ethernet is markedly more reliable than Wi-Fi for
streaming. A Pi 3B's Ethernet also shares the USB bus and tops out around
100 Mbit/s.

**5. The content itself.** 1080p60 is beyond a Pi 3B whatever you do.

**6. SD card.** A worn card slows down dramatically:

```bash
sudo hdparm -t /dev/mmcblk0
```

Under about 10 MB/s, replace it.

---

## A GPIO button does nothing

**Test the pin in isolation:**

```bash
python3 bin/gpio_buttons.py "4:echo PRESSED"
```

**If nothing prints**, it is wiring or permissions:

- Recount the pins from pin 1 — miscounting is the usual cause.
- Try a different ground pin.
- Test the switch with a multimeter (open at rest).
- `id -nG | grep gpio` — if missing: `sudo usermod -a -G gpio $USER`, then log
  out and back in.

**If it does print**, the configured command is the problem. Run it over SSH:

```bash
bash bin/stop_current_ui.sh
```

Remember shell syntax (pipes, `&&`) does not work in `REC_GPIO_BUTTONS` — the
command is tokenised, not run through a shell.

**The shutdown button specifically:**

```bash
sudo -n shutdown --help      # should not prompt for a password
sudo cat /etc/sudoers.d/010_rec-gpio-power
```

Missing? `./install.sh 60-gpio`

More detail: [60-gpio.md](60-gpio.md).

---

## Kore cannot find Kodi

1. **Remote control must be enabled inside Kodi:**
   Settings → Services → Control → Allow remote control via HTTP → On.
2. **Same network** — not a guest VLAN, no client isolation.
3. **Is the port open?** `ss -tlnp | grep 8080`
4. **Is the VPN connected?** If your LAN subnet is not allowlisted, the remote
   stops working. See [above](#ssh-drops-when-the-vpn-connects). This is the
   usual cause of a remote that worked yesterday.
5. **From outside the house**, use the Pi's Meshnet address
   (`nordvpn meshnet peer list`), not its LAN address.

---

## An add-on installs but plays nothing

**Missing adaptive streaming support** — the cause in most cases:

```bash
sudo apt-get install kodi-inputstream-adaptive
```

Then check the add-on's own settings select InputStream Adaptive.

**Geo-blocked?** Connect the VPN to the right country:

```bash
bash bin/nordvpn_connect.sh pl
```

**DRM content** (Netflix, Disney+) additionally needs Widevine — see
[20-kodi-addons.md](20-kodi-addons.md#netflix-disney-and-other-drm-services).

**An HTTP error on a `netflix.com` API URL** in `kodi.log` is an upstream
break, not your configuration — Netflix changed its API and the add-on has not
caught up. See [when it
breaks](20-kodi-addons.md#when-it-breaks-netflix-api-changes).

**Read the actual error:**

```bash
tail -100 ~/.kodi/temp/kodi.log
```

Unofficial add-ons break when services change. Check the add-on's own issue
tracker before assuming it is your setup.

---

## The Pi is slow or unstable in general

**Check the power supply first.** This is genuinely the most common cause of
"random" Raspberry Pi problems, and it never reports itself as an error:

```bash
vcgencmd get_throttled
```

**Then check, in order:**

```bash
./bin/pi_temp.sh                     # over 80 C means throttling
df -h /                              # a full SD card causes odd failures
free -h                              # 1 GB shared with the GPU on a 3B
sudo hdparm -t /dev/mmcblk0          # under ~10 MB/s means a worn card
```

**Free up space:**

```bash
sudo apt-get clean
rm -rf ~/.kodi/temp/*
sudo journalctl --vacuum-time=7d
```

---

## Everything restarts when I SSH in

`autostart.sh` should exit immediately unless it is running on `/dev/tty1`.
Check the guard is intact:

```bash
grep -A5 "REC_FORCE_AUTOSTART" bin/autostart.sh
grep -A3 "rpi-entertainment-center" ~/.bashrc
```

Re-run `./install.sh 00-base` to restore the hook.

If you deliberately want to start the services over SSH:

```bash
REC_FORCE_AUTOSTART=1 bash bin/autostart.sh
```

---

## Scripts fail with "command not found"

**Not executable?** Common after copying the repo across a filesystem that
drops permission bits:

```bash
chmod +x bin/*.sh bin/*.py install.sh modules/*/install.sh
```

**Windows line endings?** If you edited a file on Windows:

```bash
sudo apt-get install dos2unix
dos2unix bin/*.sh
```

The symptom is a confusing `bad interpreter: /bin/bash^M`.

**Missing config?**

```bash
ls -l config.sh
cp config.example.sh config.sh && chmod 600 config.sh
```

**Moved the repository?** The scripts locate themselves, but `.bashrc` holds
the old path. Re-run:

```bash
./install.sh 00-base
```

---

## Where the logs are

| What | Where |
|---|---|
| Kodi | `~/.kodi/temp/kodi.log`, `~/.kodi/temp/kodi.old.log` |
| RetroPie install | `~/RetroPie-Setup/logs/` |
| X / desktop | `~/.xsession-errors` |
| System | `sudo journalctl -b` (this boot), `-f` (follow) |
| NordVPN | `sudo journalctl -u nordvpnd -n 50` |
| Apache | `/var/log/apache2/error.log` |
| Tvheadend | `sudo journalctl -u tvheadend -n 50` |
| No-IP | `sudo journalctl -u noip2 -n 50` |

The project's own background scripts log to the console session that started
them (tty1), so their output is visible on the TV before a UI takes over. To
watch one directly, run it in the foreground:

```bash
bash bin/nordvpn_monitor.sh
```

---

## Starting over

**Reset the configuration** to defaults:

```bash
mv config.sh config.sh.old
cp config.example.sh config.sh
chmod 600 config.sh
```

**Reinstall a module** — they are all idempotent:

```bash
./install.sh 50-ui-rotation
```

**Undo an installer's edits.** Every file an installer touches is backed up
once, the first time, to `<file>.rec-backup`:

```bash
ls -la ~/.bashrc.rec-backup /etc/apache2/conf-available/security.conf.rec-backup
```

**Remove the autostart hook** without uninstalling anything:

```bash
sed -i '/>>> rpi-entertainment-center >>>/,/<<< rpi-entertainment-center <<</d' ~/.bashrc
```

**Reinstall the whole system:** back up the things listed in
[INSTALL.md §13](../INSTALL.md#13-restoring-a-previous-installation) first —
in particular `config.sh`, `~/.kodi/userdata/`, `~/RetroPie/roms/` and
`/opt/retropie/configs/`.

---

## Still stuck?

Gather this before asking anyone:

```bash
./bin/doctor.sh > /tmp/doctor.txt 2>&1
uname -a                    >> /tmp/doctor.txt
cat /etc/os-release         >> /tmp/doctor.txt
vcgencmd get_throttled      >> /tmp/doctor.txt
```

**Redact `config.sh` before sharing it** — it contains your VPN token.
