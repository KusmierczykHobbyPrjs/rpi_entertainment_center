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
[INSTALL.md §12](../INSTALL.md#12-restoring-a-previous-installation) first —
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
