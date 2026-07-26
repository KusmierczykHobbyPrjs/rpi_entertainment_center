# 60-gpio — physical buttons

Buttons wired to the GPIO header let the Pi be used with no remote at all —
and give you the only safe way to power it off while it is showing a game.

```bash
./install.sh 60-gpio
```

**Prerequisites:** `00-base`. Wiring: see [HARDWARE.md](HARDWARE.md#gpio-buttons).

---

## What it does

1. Installs `python3-rpi.gpio`.

   > Older Raspberry Pi guides tell you to `apt-get install wiringpi`.
   > **Do not** — WiringPi was deprecated by its author and is no longer
   > packaged. `RPi.GPIO` is the maintained replacement and is what this
   > project uses.
2. Validates the button map in `config.sh`.
3. Installs a narrowly-scoped sudoers rule so the power button works without a
   password.
4. Adds you to the `gpio` group.

---

## The default buttons

| BCM pin | Physical pin | Function |
|---|---|---|
| 3 | 5 | Power off — and power **on** again |
| 4 | 7 | Switch UI |
| 17 | 11 | Next VPN country |
| 22 | 15 | Play / pause |
| 27 | 13 | Play radio |

Change them in `REC_GPIO_BUTTONS` in `config.sh`:

```bash
REC_GPIO_BUTTONS=(
    "3:sudo shutdown now"
    "4:bash $REC_BIN/stop_current_ui.sh"
    "17:bash $REC_BIN/nordvpn_rotate.sh"
    "22:kodi-send -a PlayerControl(Play)"
    "27:kodi-send -a PlayPvrRadio"
)
```

Format: `BCM_PIN:command with arguments`. `$REC_BIN` expands to this
repository's `bin/` directory.

A list of useful commands to bind is in
[CONFIGURATION.md](CONFIGURATION.md#gpio-buttons).

---

## Wiring

Each button connects its GPIO pin to **any** ground pin. That is the entire
circuit — no resistor needed, because the script enables the Pi's internal
pull-up:

```
    GPIO pin ────o  o──── GND
                 button
```

The pin idles at 3.3 V; pressing the button pulls it to 0 V and the script
triggers on that falling edge.

**GPIO 3 is special:** shorting it to ground also wakes a halted Pi. So one
button both shuts the Pi down and turns it back on. Wire it between physical
pins 5 and 6, which are conveniently adjacent. No other pin can do this.

Full pinout, which pins to avoid, and photographs:
[HARDWARE.md](HARDWARE.md#gpio-buttons) and
[`photos/gpio control/`](../photos/gpio%20control/).

---

## How it works

`gpio_buttons.sh` reads the map from `config.sh` and hands it to
`gpio_buttons.py`, which does the GPIO work.

**One process handles every button.** The earlier version of this project
started a separate Python interpreter per pin — five of them, roughly 10 MB
each, on a machine with 1 GB shared with the GPU.

Commands are tokenised with `shlex` and run with `shell=False`, so a stray
character in `config.sh` cannot turn into shell injection. The trade-off is
that shell syntax (pipes, `&&`, redirection) does not work — wrap it in a
script if you need that.

### Debouncing

Mechanical buttons bounce for a few milliseconds; without handling, one press
fires several times. Two layers:

- **300 ms hardware debounce** in `RPi.GPIO` itself.
- **1 second repeat guard** in the handler, because the actions here are
  heavyweight (shutdown, UI switch, VPN reconnect) and a second press that
  soon is almost always an accident.

`stop_current_ui.sh` and `nordvpn_rotate.sh` additionally rate-limit
themselves to one run per 5 seconds, since they are also reachable from Kodi
and from a phone.

### Passwordless shutdown

The button listener runs as your normal user, and a button press cannot type a
password. Rather than running the whole listener as root, the installer allows
exactly the power commands:

```
/etc/sudoers.d/010_rec-gpio-power
    pi ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /usr/sbin/shutdown, /usr/sbin/reboot
```

The file is validated with `visudo -c` before installation — a syntax error in
a sudoers file can lock you out of `sudo` entirely.

---

## Verify

```bash
./bin/doctor.sh gpio
```

It checks the library is available, that every configured command actually
exists, that the listener is running, and that the sudoers rule is in place.

**Test a button** by running the listener in the foreground:

```bash
python3 bin/gpio_buttons.py "4:echo BUTTON-4-WORKS"
```

Each press should print a line. Ctrl-C to stop.

---

## Troubleshooting

**Nothing happens when I press a button**

Test that pin alone first:

```bash
python3 bin/gpio_buttons.py "4:echo PRESSED"
```

If that prints nothing, the problem is wiring or permissions:

- Recount the pins from pin 1 — miscounting is the usual cause.
- Try a different ground pin.
- Test the switch with a multimeter (open at rest, closed when pressed).
- Check group membership: `id -nG | grep gpio`. If it is missing:
  `sudo usermod -a -G gpio $USER`, then log out and back in.

If that *does* print, the problem is the configured command — see below.

**One press triggers several times**

The debounce is not taking effect, which usually means a particularly bouncy
switch. Raise `BOUNCE_MS` in `bin/gpio_buttons.py`, or add a 100 nF capacitor
across the switch.

**The button works but the command does not**

Run the exact command from `config.sh` over SSH and read the error:

```bash
bash bin/stop_current_ui.sh
```

Remember that shell syntax does not work in `REC_GPIO_BUTTONS` — put it in a
script instead.

**The shutdown button does nothing**

- Check the sudoers file: `sudo cat /etc/sudoers.d/010_rec-gpio-power`
- Test it: `sudo -n shutdown --help` — it should not prompt.
- Missing? Re-run `./install.sh 60-gpio`.

**The Pi will not power back on with the GPIO 3 button**

- It must be *halted*, not powered off at the wall.
- The button has to be on GPIO 3 specifically — physical pin 5. No other pin
  has this behaviour.

**"RuntimeError: Failed to add edge detection"**

Another process already holds that pin. Find it:

```bash
pgrep -af gpio_buttons.py
```

Kill the stray copy. This happens if you start the listener manually while
`autostart.sh` has already started one.

**The listener is not running after boot**

```bash
pgrep -af gpio_buttons.py
grep -A3 "rpi-entertainment-center" ~/.bashrc
```

It starts from `autostart.sh`, which only runs on the physical console. Over
SSH it is normal for this to be absent until you reboot.
