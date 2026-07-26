# Hardware

Parts, wiring and the physical build. Only the Pi itself is mandatory —
buttons and tuners are optional extras.

---

## Parts list

### Essential

| Part | Notes |
|---|---|
| Raspberry Pi 3B or newer | A 3B handles 720p video and retro gaming up to the PlayStation era. A Pi 4 is noticeably better for 1080p. |
| **Power supply, 2.5 A or more** | See the warning below. This is not optional. |
| SD card, 16 GB+, class 10 | 32 GB if you want ROMs or TV recordings. |
| HDMI cable | |
| Ethernet cable | Wi-Fi works, but streams less reliably. |

> ### About the power supply
>
> An underpowered Pi does not report an error. It throttles the CPU, drops USB
> devices, corrupts the SD card and generally behaves like failing hardware.
> Phone chargers are the usual culprit — many claim 2 A and deliver
> considerably less under load.
>
> Check whether it has ever happened:
>
> ```bash
> vcgencmd get_throttled
> ```
>
> `throttled=0x0` is good. Anything else means under-voltage or overheating
> has occurred since boot. `./bin/doctor.sh` checks this too.

### Optional

| Part | For |
|---|---|
| USB gamepad | RetroPie. Almost any pad works; generic ones may need manual configuration. |
| 4–5 momentary push buttons | GPIO control. Any normally-open tactile switch. |
| Female-to-female jumper wires | Wiring buttons to the header. |
| USB DVB-T/T2 tuner | Tvheadend — live broadcast TV. |
| Small heatsink or fan | Only if `vcgencmd measure_temp` regularly exceeds 70 °C. |
| Case with cut-outs | See [the case](#the-case) below. |

---

## GPIO buttons

### Wiring

Each button connects a GPIO pin to **any** ground pin. That is the whole
circuit:

```
    GPIO pin ────o  o──── GND
                 button
```

**No resistor is needed.** The listener enables the Pi's internal pull-up, so
the pin idles high (3.3 V) and pressing the button pulls it to 0 V. The script
triggers on that falling edge.

### Pin numbering

The project uses **BCM numbering** (the `GPIO n` names), not physical header
positions. `config.sh` entries like `"17:..."` mean GPIO 17, which is physical
pin 11.

```
        3V3  (1) (2)  5V
      GPIO2  (3) (4)  5V
      GPIO3  (5) (6)  GND      ← power button + its ground
      GPIO4  (7) (8)  GPIO14
        GND  (9) (10) GPIO15
     GPIO17 (11) (12) GPIO18
     GPIO27 (13) (14) GND
     GPIO22 (15) (16) GPIO23
        3V3 (17) (18) GPIO24
     GPIO10 (19) (20) GND
      GPIO9 (21) (22) GPIO25
     GPIO11 (23) (24) GPIO8
        GND (25) (26) GPIO7
      GPIO0 (27) (28) GPIO1
      GPIO5 (29) (30) GND
      GPIO6 (31) (32) GPIO12
     GPIO13 (33) (34) GND
     GPIO19 (35) (36) GPIO16
     GPIO26 (37) (38) GPIO20
        GND (39) (40) GPIO21
```

Ground pins: 6, 9, 14, 20, 25, 30, 34, 39 — any of them will do.

### The default button map

| BCM | Physical | Function | Command |
|---|---|---|---|
| 3 | 5 | Power off / on | `sudo shutdown now` |
| 4 | 7 | Switch UI | `stop_current_ui.sh` |
| 17 | 11 | Next VPN country | `nordvpn_rotate.sh` |
| 22 | 15 | Play / pause | `kodi-send -a PlayerControl(Play)` |
| 27 | 13 | Play radio | `kodi-send -a PlayPvrRadio` |

Change any of them in `REC_GPIO_BUTTONS` in `config.sh`.

### Why GPIO 3 for power

**GPIO 3 (physical pin 5) is special: shorting it to ground wakes a halted Pi.**

So the same button does both jobs — press it while running and the script
shuts the Pi down; press it while halted and the hardware powers it back on.
One button, full power control, no other pin can do this.

Wire it between physical pins 5 and 6, which are conveniently adjacent.

Note that GPIO 2 and GPIO 3 have permanent on-board pull-up resistors (they
are the I²C pins). That does not matter here — the internal pull-up the script
requests is simply redundant on this pin.

### Choosing other pins

Avoid these, which have other jobs:

- **GPIO 0, 1** — reserved for HAT identification
- **GPIO 14, 15** — the serial console
- **GPIO 7–11** — SPI, if you ever enable it
- **GPIO 2** — I²C data, if you ever enable it

Everything else is free. GPIO 4, 17, 27, 22, 5, 6, 13, 19, 26 are all good
choices.

### Testing a button

Run the listener in the foreground and press it:

```bash
python3 bin/gpio_buttons.py "4:echo BUTTON-4-WORKS"
```

Each press should print a line. If nothing happens:

- confirm the wire really is on the pin you think — recount from pin 1
- try a different ground pin
- test the switch itself with a multimeter (it should be open at rest)
- check the user is in the `gpio` group: `id -nG | grep gpio`

Debouncing is handled in software: 300 ms of hardware debounce plus a 1-second
repeat guard, so one press produces exactly one action.

---

## The case

Photographs of the build are in [`photos/rpi_case/`](../photos/rpi_case/).

What matters when building or choosing one:

- **Access to the GPIO header.** Most cases cover it entirely. Look for one
  with a cut-out, or make one.
- **Somewhere to mount the buttons.** Front-facing is far more usable than
  rear-facing — you will press these without looking.
- **Ventilation.** The Pi is under sustained load while transcoding or
  emulating. A sealed case pushes it towards the 80 °C throttle point.
- **Cable strain relief.** HDMI and power sit on adjacent edges and a tug on
  either can pull the board.

---

## Gamepads

Most USB gamepads work without configuration. EmulationStation prompts you to
map the buttons the first time it starts.

Generic pads sometimes fail to be recognised by RetroArch and need their
vendor and product IDs adding by hand. Find them with:

```bash
lsusb
cat /proc/bus/input/devices | grep -A5 -i joystick
```

Then add to the autoconfig file for your pad in
`/opt/retropie/configs/all/retroarch/autoconfig/`:

```
input_vendor_id = "121"
input_product_id = "6"
```

(Those values are an example from a DragonRise generic pad — use your own.)

Kodi uses the same gamepad through `kodi-peripheral-joystick`, so one
controller drives both environments.

---

## TV tuners

For live broadcast TV (module `25-tvheadend`) you need a USB DVB tuner
matching your region: DVB-T/T2 for terrestrial in most of Europe, DVB-S/S2 for
satellite, DVB-C for cable.

After plugging one in:

```bash
dmesg | tail -20        # should mention the tuner and any firmware it loaded
ls /dev/dvb/            # an adapter0 directory should appear
```

If `dmesg` complains about missing firmware, install `firmware-linux-nonfree`
or fetch the specific `.fw` file the log names into `/lib/firmware/`.

---

## Storage

USB drives need extra packages for the common filesystems — module `00-base`
installs them:

```bash
sudo apt install ntfs-3g exfat-fuse exfatprogs
```

Without these, an NTFS drive full of films simply does not mount, with no
useful error.

Mount one manually:

```bash
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb
sudo chmod 775 /mnt/usb
```

To mount it automatically at boot, get the drive's UUID with `sudo blkid` and
add a line to `/etc/fstab`:

```
UUID=xxxx-xxxx  /mnt/usb  auto  nofail,x-systemd.device-timeout=10,uid=pi,gid=pi  0  0
```

**`nofail` matters.** Without it, the Pi refuses to finish booting when the
drive is absent — and it will be absent eventually.

---

## Temperature

```bash
./bin/pi_temp.sh
```

| Reading | Meaning |
|---|---|
| under 60 °C | idle, fine |
| 60–70 °C | under load, fine |
| 70–80 °C | warm — check ventilation |
| over 80 °C | throttling; video stutters and emulation slows |

The Pi does not report throttling as an error; it just gets slower. If
performance degrades after a while under load, check here first.
