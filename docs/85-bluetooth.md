# 85-bluetooth — the Pi as a Bluetooth speaker

Let a phone, laptop or tablet connect to the Pi and play through whatever is
wired to the Pi's **3.5 mm jack** — a hi-fi, powered speakers, an old
amplifier.

```bash
./install.sh 85-bluetooth
```

**Prerequisites:** `00-base`.

---

## Which direction this is

| | |
|---|---|
| **The Pi is the sink** ← *this module* | A phone connects **to** the Pi. Sound leaves via the Pi's jack. The Pi behaves like a Bluetooth speaker. |
| The Pi is the source | The Pi connects **to** a Bluetooth speaker. Not what this module does — pair one from the desktop and set it as the default output. |

---

## Why it needs more than pairing

Getting a phone to pair is the easy part. Three things have to line up:

**1. The Pi has to look like a speaker.** bluez advertises a Raspberry Pi with
the *computer* device class. Many phones pair happily and then never offer
"connect for media audio", because they do not believe it is an audio device.
This module sets the class to `0x200414` — Audio/Video, portable audio — and
sets `DiscoverableTimeout = 0` so it stays findable rather than for three
minutes after a reboot.

**2. Something has to accept the pairing request.** There is no keyboard on
the Pi. `bt-agent` runs as a service with `--capability=NoInputNoOutput`,
giving "just works" pairing with no PIN.

**3. The audio stack has to be running when Kodi is.** This is the part that
differs between releases, and the part that catches people out.

---

## PipeWire (Bookworm and later)

Good news: **WirePlumber links the incoming Bluetooth stream to the output by
itself.** There is no loopback to configure — a phone connects and the audio
appears at the default sink.

The one real problem is *when* PipeWire runs. PipeWire and WirePlumber are
**per-user services**, started at login. Kodi and EmulationStation run from a
console with no graphical session, so without help the speaker works on the
desktop and goes silent everywhere else.

The fix is lingering:

```bash
sudo loginctl enable-linger $USER
```

That keeps your user's systemd instance — and therefore PipeWire — running
from boot whether or not anyone is logged in. It replaces PulseAudio's old
system mode and is far less invasive: no shared audio session, nothing running
as a system daemon, no upstream disapproval.

### Packages that matter

```bash
sudo apt install pipewire pipewire-pulse wireplumber libspa-0.2-bluetooth
```

**`libspa-0.2-bluetooth` is the one to check.** It is the SPA plugin that
gives PipeWire its Bluetooth support; without it a phone pairs, connects, and
no audio node ever appears.

### Sound quality

The module writes `~/.config/wireplumber/wireplumber.conf.d/51-rec-bluetooth.conf`:

```
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source ]
  bluez5.enable-sbc-xq = true
}
```

`a2dp_sink` is already the default; it is listed so the intent is visible.
**SBC-XQ** is the useful part — a higher-bitrate SBC profile that essentially
every source supports and which sounds clearly better than baseline SBC.

---

## PulseAudio (Bullseye and earlier)

PulseAudio also runs per session, and the answer there is system mode — one
daemon for the whole machine, started by systemd.

> ### The trap in system mode
>
> `/etc/pulse/system.pa` does **not** load the Bluetooth modules, unlike
> `default.pa`. Switch to system mode without adding them and you get the most
> confusing possible failure: the phone pairs, connects, shows itself as
> playing — and no sound ever reaches the jack.
>
> The module appends them. If you set this up by hand, do not skip it.

---

## Connecting a phone

1. Phone → Settings → Bluetooth.
2. Pick the Pi (the name you chose at install; the hostname by default) and
   pair. **There is no PIN.**
3. Play something.

```bash
bluetoothctl devices        # what is paired
wpctl status                # the phone appears here once connected
```

---

## Verify

```bash
./bin/doctor.sh bluetooth
```

It checks the device class, the Audio Sink profile, the pairing agent,
`libspa-0.2-bluetooth`, and — on PipeWire — whether lingering is enabled,
which is the difference between working under Kodi and not.

---

## Security

`NoInputNoOutput` pairing means **anyone within Bluetooth range (~10 m) can
pair and play audio** while the Pi is discoverable. There is no PIN. For a
living room that is usually the point — guests can put music on without being
handed a password.

If that is not what you want:

```bash
sudo systemctl disable --now bt-agent      # already-paired devices still work
sudo bluetoothctl discoverable off
```

Pairing grants audio only: no files, no network, no shell.

---

## Troubleshooting

**Shutdown hangs on `Job bt-agent.service/stop running (Xs / 1min 30s)`**

`bt-agent` does not exit on SIGTERM. With systemd's default 90-second stop
timeout, every shutdown waits it out.

`1min 30s` in that message is the giveaway: it is the *default* timeout, so the
unit predates the fix. Update and re-run:

```bash
cd ~/rpi_entertainment_center && git pull
./install.sh 85-bluetooth
```

The unit now uses `KillSignal=SIGKILL` with `TimeoutStopSec=5`. `bt-agent` is
a D-Bus agent with no state to flush — bluez drops the registration when the
connection closes — so killing it outright costs nothing and makes shutdown
immediate.

To patch an existing install without re-running the module:

```bash
sudo mkdir -p /etc/systemd/system/bt-agent.service.d
sudo tee /etc/systemd/system/bt-agent.service.d/override.conf >/dev/null <<'EOF'
[Service]
KillSignal=SIGKILL
TimeoutStopSec=5
EOF
sudo systemctl daemon-reload
```

**The installer hung, or the unit sits in `activating`**

A different fault with the same feel. Earlier versions ran `bluetoothctl` as
`ExecStartPre`; it reads stdin, and under systemd there is no terminal, so it
waited forever.

```bash
systemctl is-active bt-agent            # "activating" = stuck
sudo systemctl disable --now bt-agent
sudo systemctl reset-failed bt-agent
```

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#shutdown-takes-2-minutes-or-an-install-step-hangs).

**"Couldn't pair because of an incorrect PIN or passkey"**

There is no PIN — `bt-agent` runs with `NoInputNoOutput`, which means "Just
Works" pairing. That message almost never means a wrong code was typed.

**1. A stale bond on either side.** The usual cause, and confirmed in
practice: a failed attempt leaves a link key on one end that no longer matches
the other, and the mismatch surfaces as a PIN failure. `bluetoothctl remove`
followed by a fresh pairing fixes it. Clear *both* sides:

```bash
bluetoothctl devices                    # find the phone
bluetoothctl remove AA:BB:CC:DD:EE:FF
```

Then on the phone: Bluetooth → the Pi → **Forget this device**. Pair again.

**2. A second agent is answering.** Only one agent can be the default. If a
desktop session is running, `blueman-applet` or the GNOME agent registers one
too — and if it wins, it silently prompts on a screen nobody is watching while
the phone times out.

```bash
# watch the pairing attempt live, then pair from the phone
sudo journalctl -u bt-agent -u bluetooth -f
```

`bt-agent` should log `Agent registered` and `Default agent requested`. If the
request never reaches it, something else took the default. Switch to Kodi or
the console first — away from the desktop — and try again, or stop the
competing applet.

**3. bt-agent is not actually running.**

```bash
systemctl is-active bt-agent
sudo systemctl restart bt-agent
```

**4. Pairing while not discoverable.** Some phones will initiate a bond
against a cached address and fail oddly.

```bash
bluetoothctl show | grep Discoverable    # want: yes
```

**The Pi does not appear on the phone**

```bash
bluetoothctl show          # want: Powered: yes, Discoverable: yes
systemctl status bluetooth bt-agent
```

`Discoverable: no` means the agent service is not running — it is what turns
discoverability on at boot.

**The phone shows the hostname instead of the name I chose**

Which mechanism sets the adapter name varies by bluez version, so the module
sets all three. Check what is actually advertised:

```bash
bluetoothctl show | grep -E 'Name|Alias'
```

To change it by hand:

```bash
bluetoothctl system-alias "Living Room"      # immediate, no restart
sudo hostnamectl set-hostname --pretty "Living Room"
```

`hostnamectl --pretty` sets a free-text label only — it does not affect
`ssh pi@raspberrypi`.

> Re-running the module offers the **currently advertised** name as the
> default, not the hostname. Earlier versions offered the hostname, which made
> it look as though a previously chosen name had not stuck when it had.

**It pairs, but the phone offers no "media audio" option**

The device class is wrong; the phone thinks the Pi is a computer.

```bash
bluetoothctl show | grep Class     # want 0x200414
sudo systemctl restart bluetooth   # if main.conf was edited but not applied
```

**It connects but there is no sound**

```bash
wpctl status                       # does the phone appear as a source?
wpctl get-volume @DEFAULT_AUDIO_SINK@
dpkg -l libspa-0.2-bluetooth       # installed?
```

If the phone does not appear at all, `libspa-0.2-bluetooth` is missing.

**Sound works on the desktop but stops under Kodi**

Lingering is not enabled — the single most common cause on Bookworm and later:

```bash
loginctl show-user $USER -p Linger      # want Linger=yes
sudo loginctl enable-linger $USER
```

**It is quiet**

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%
```

Use `wpctl`, **never** `amixer` — WirePlumber overwrites ALSA at every boot.
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#sound-is-too-quiet-even-at-maximum-volume).

The Pi's jack is PWM rather than a DAC and is quiet by construction; HDMI or a
USB DAC is a large improvement.

**Audio is choppy**

Wi-Fi and Bluetooth share the 2.4 GHz radio on a Pi 3B. Wired Ethernet helps
considerably. Moving the phone closer helps too.

**It does not reconnect after a reboot**

Run `bluetoothctl` and `trust <MAC>`. Without trust, a device pairs but will
not reconnect on its own.

---

## Sources

- [Using a Raspberry Pi as a Bluetooth speaker with PipeWire and WirePlumber](https://www.collabora.com/news-and-blog/blog/2022/09/02/using-a-raspberry-pi-as-a-bluetooth-speaker-with-pipewire-wireplumber/)
  — Collabora; the reference for the PipeWire path.
- [Bluetooth audio on the Raspberry Pi](https://howchoo.com/pi/bluetooth-raspberry-pi)
  — pairing and the bluez side.
- [How can I make PulseAudio run as root?](https://stackoverflow.com/questions/66775654/how-can-i-make-pulseaudio-run-as-root)
  — the PulseAudio system-mode question, for Bullseye.
- [Bluetooth assigned numbers](https://www.bluetooth.com/specifications/assigned-numbers/)
  — where the `0x200414` device class comes from.
