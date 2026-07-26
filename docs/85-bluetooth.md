# 85-bluetooth — the Pi as a Bluetooth speaker

Let a phone, laptop or tablet connect to the Pi and play its music through
whatever is plugged into the Pi's **3.5 mm jack** — a hi-fi, powered speakers,
an old amplifier.

```bash
./install.sh 85-bluetooth
```

**Prerequisites:** `00-base`.

---

## Which direction this is

Bluetooth audio has two ends, and they need completely different setups:

| | |
|---|---|
| **The Pi is the sink** ← *this module* | A phone connects **to** the Pi. Sound leaves via the Pi's jack. The Pi behaves like a Bluetooth speaker. |
| The Pi is the source | The Pi connects **to** a Bluetooth speaker. Not what this module does. |

If you want the second one, pair a speaker from the desktop with **blueman**
and set it as the default sink — nothing here is needed for that.

---

## Why it needs more than pairing

Getting a phone to pair is the easy part. Three things have to line up, and
most guides only cover the first:

**1. The Pi has to look like a speaker.** By default bluez advertises a
Raspberry Pi with the *computer* device class (`0x002c0000` out of the box).
Many phones will pair with it happily and then never offer "connect for media
audio", because they do not believe it is an audio device. This module sets
the class to `0x200414` — Audio/Video, portable audio.

It also sets `DiscoverableTimeout = 0` and `PairableTimeout = 0`, so the Pi
stays visible indefinitely instead of for three minutes after a reboot. An
appliance with no screen needs to be findable whenever someone walks in.

**2. Something has to accept the pairing request.** There is no keyboard on
the Pi to confirm a PIN. `bt-agent` runs as a service with
`--capability=NoInputNoOutput`, which means "just works" pairing — the phone
shows no PIN prompt and the Pi accepts.

**3. PulseAudio has to carry the stream to the jack.** When a phone connects,
PulseAudio sees it as a *source*, and `module-bluetooth-policy` loops it
through to the default sink. That module is loaded from
`/etc/pulse/default.pa` — a **per-user** config.

That last point is the one that bites. Per-user PulseAudio only exists inside
a login session, so the Pi works as a speaker on the desktop and goes silent
the moment you switch to Kodi or the console. System-mode PulseAudio — one
daemon for the whole machine, started at boot — fixes it.

> ### The trap in system mode
>
> `/etc/pulse/system.pa` does **not** load the Bluetooth modules, unlike
> `default.pa`. Switch to system mode without adding them and you get the most
> confusing possible failure: the phone pairs, connects, shows itself as
> playing — and no sound ever reaches the jack.
>
> The installer appends them. If you set this up by hand, do not skip it.

---

## What the installer does

1. Installs `bluez`, `bluez-tools`, `pulseaudio`, `pulseaudio-module-bluetooth`.
2. Adds you to `bluetooth`, `audio` and `pulse-access`.
3. Rewrites `/etc/bluetooth/main.conf`:
   `Class = 0x200414`, `DiscoverableTimeout = 0`, `PairableTimeout = 0`,
   `AlwaysPairable = true`, and the name phones will show.
4. Installs `bt-agent.service` to accept pairing without a keyboard.
5. Routes output to the analogue jack (`raspi-config nonint do_audio 1`).
6. Offers system-mode PulseAudio, **with** the Bluetooth modules added to
   `system.pa` and the `pulse` user put in the `bluetooth` and `audio` groups.

Every file it edits is backed up once to `<file>.rec-backup`.

---

## Connecting a phone

1. Phone → Settings → Bluetooth.
2. Pick the Pi from the list (the name you chose at install; the hostname by
   default) and pair. **There is no PIN.**
3. Play something. Sound comes out of the Pi's 3.5 mm jack.

The Pi stays discoverable, so it appears without anyone touching it.

Check what is paired:

```bash
bluetoothctl devices
```

---

## Verify

```bash
./bin/doctor.sh bluetooth
```

With a phone connected and playing:

```bash
pactl list sources short | grep bluez    # the phone as an audio source
pactl list sinks short                   # the jack
pactl list modules short | grep blue     # discover + policy must be loaded
```

---

## Security

`NoInputNoOutput` pairing means **anyone within Bluetooth range (~10 m) can
pair and play audio** while the Pi is discoverable. There is no PIN to stop
them. For a living room that is usually the point — guests can put music on
without being handed a password.

If that is not what you want:

```bash
# stop advertising; already-paired devices still reconnect
sudo systemctl disable --now bt-agent
sudo bluetoothctl discoverable off
```

Then pair new devices deliberately by re-enabling it for a minute.

Note that pairing grants audio only. It gives no access to files, the network
or a shell.

---

## Troubleshooting

**The Pi does not appear on the phone at all**

```bash
bluetoothctl show          # want: Powered: yes, Discoverable: yes
systemctl status bluetooth bt-agent
```

If `Discoverable: no`, the agent service is not running — it is what turns
discoverability on at boot.

**It pairs, but the phone offers no "media audio" option**

The device class is wrong — the phone thinks the Pi is a computer. Check:

```bash
bluetoothctl show | grep Class     # want 0x200414
```

If it still shows `0x002c0000`, `/etc/bluetooth/main.conf` was not applied:
`sudo systemctl restart bluetooth`.

**It connects but there is no sound**

The most common case, and usually one of these:

```bash
# 1. Are the Bluetooth modules loaded at all?
pactl list modules short | grep blue

# 2. Is the phone showing up as a source?
pactl list sources short | grep bluez

# 3. Is the jack the default sink, and turned up?
pactl list sinks short
alsamixer
```

If (1) is empty **and** you enabled system mode, `system.pa` is missing the
module lines — see the trap above. Re-run `./install.sh 85-bluetooth`.

**Sound works on the desktop but stops under Kodi**

Exactly what system mode is for. Re-run the module and say yes this time.

**Audio is choppy**

- Wi-Fi and Bluetooth share the same 2.4 GHz radio on a Pi 3B. Wired Ethernet
  makes a large difference.
- Move the phone closer, or the Pi away from other 2.4 GHz sources.
- The analogue jack on a Pi 3B is noisy by design; a USB DAC is a real
  improvement if quality matters.

**The phone reconnects but audio goes to HDMI**

```bash
sudo raspi-config nonint do_audio 1     # force the jack
pactl set-default-sink $(pactl list sinks short | awk '/analog/{print $2; exit}')
```

**`pactl` says "Connection refused"**

No PulseAudio daemon is reachable. In system mode check
`systemctl status pulseaudio`; otherwise you are on a console with no session
— which is the problem system mode solves.

**Bluetooth broke after enabling system mode**

Log out and back in so your new group membership applies:

```bash
sudo usermod -a -G pulse-access $USER
```

---

## Sources

- [Bluetooth audio on the Raspberry Pi](https://howchoo.com/pi/bluetooth-raspberry-pi)
  — pairing and the bluez side.
- [How can I make PulseAudio run as root?](https://stackoverflow.com/questions/66775654/how-can-i-make-pulseaudio-run-as-root)
  — the system-mode question, and why it is needed for console and Kodi audio.
- [PulseAudio: what is wrong with system mode](https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/WhatIsWrongWithSystemWide/)
  — upstream's own account of the trade-offs. Read before committing to it.
- [Bluetooth assigned numbers: baseband device classes](https://www.bluetooth.com/specifications/assigned-numbers/)
  — where `0x200414` comes from.
