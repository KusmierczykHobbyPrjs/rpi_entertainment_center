# 60-gpio — physical buttons

Buttons wired to the GPIO header let the Pi be used with no remote at all —
and give you the only safe way to power it off while it is showing a game.

```bash
./install.sh 60-gpio
```

**Prerequisites:** `00-base`. Wiring: see [HARDWARE.md](HARDWARE.md#gpio-buttons).

---

## What it does

1. Makes sure the `RPi.GPIO` Python module is available — **without
   replacing whatever already provides it**.

   > **Two packages provide `RPi.GPIO`, and they conflict.** Installing one
   > makes apt remove the other:
   >
   > | Package | Notes |
   > |---|---|
   > | `python3-rpi.gpio` | The original. Direct register access. Works on Pi 2/3/4/Zero; **does not work on a Pi 5** (the RP1 chip needs different drivers). |
   > | `python3-rpi-lgpio` | Drop-in replacement over `lgpio`, using the modern character-device interface. Shipped by default on Bookworm and later; the only option on a Pi 5. |
   >
   > If the module already imports, this module installs nothing. Only when
   > neither is present does it choose — `python3-rpi-lgpio` on a Pi 5 or on
   > Bookworm and later, otherwise the original.
   >
   > An earlier version installed `python3-rpi.gpio` unconditionally, which
   > silently uninstalled the OS-provided `python3-rpi-lgpio`. Harmless on a
   > Pi 3B, where both work — but it should not have made that decision for
   > you. If it happened to you and you want the original back:
   >
   > ```bash
   > sudo apt install python3-rpi-lgpio      # removes python3-rpi.gpio
   > ```
   >
   > Older guides also tell you to install **`wiringpi`**. Do not — it was
   > deprecated by its author and is no longer packaged.

   Check which one you have:

   ```bash
   ./bin/doctor.sh gpio
   ```
2. Validates the button map in `config.sh`.
3. Installs a narrowly-scoped sudoers rule so the power button works without a
   password.
4. Adds you to the `gpio` group.

---

## The default buttons

| BCM pin | Physical pin | Function |
|---|---|---|
| 3 | 5 | Power off (hold 1.5 s) — and power **on** again |
| 4 | 7 | Switch UI |
| 17 | 11 | Next VPN country |
| 22 | 15 | Play / pause |
| 27 | 13 | Play radio |

Change them in `REC_GPIO_BUTTONS` in `config.sh`:

```bash
REC_GPIO_BUTTONS=(
    "3@1500:sudo shutdown now"
    "4:bash $REC_BIN/stop_current_ui.sh"
    "17:bash $REC_BIN/nordvpn_rotate.sh"
    "22:kodi-send -a PlayerControl(Play)"
    "27:kodi-send -a PlayPvrRadio"
)
```

Format: `BCM_PIN:command` or `BCM_PIN@HOLD_MS:command`. `$REC_BIN` expands to
this repository's `bin/` directory.

`HOLD_MS` is how long the pin must stay low before the press is believed —
50 ms by default, which rejects crosstalk from a neighbouring button. Shutdown
gets 1500 ms so it needs a deliberate press-and-hold.

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

### Debouncing and glitch rejection

Three layers, because a falling edge on its own means very little:

- **300 ms hardware debounce** in `RPi.GPIO` — mechanical contacts bounce for
  a few milliseconds, and without this one press fires several times.
- **A hold check.** The pin must still read LOW after `HOLD_MS` (50 ms by
  default). This is what rejects electrical crosstalk: a neighbouring button
  can induce a genuine edge, but not hold the line down.
- **1 second repeat guard** in the handler, because the actions are heavyweight
  (shutdown, UI switch, VPN reconnect) and a second press that soon is almost
  always an accident.

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

**Pressing one button fires a different one — often shutdown**

Electrical crosstalk, not a software mix-up. Two things make it likely:

- the internal pull-ups are weak (~50 kΩ), so a line is easily disturbed
- header pins are physically adjacent — **GPIO 3 is pin 5, GPIO 4 is pin 7** —
  and button wiring is usually unshielded

Pressing one button couples a transient into its neighbour and produces a
genuine falling edge on a pin nobody touched.

**The software now rejects these.** An edge is not a press: the pin must stay
low for `HOLD_MS` (default 50 ms) before the command runs. A real press holds
it low far longer; a glitch has already gone. Rejections are logged rather
than silent:

```
[gpio] GPIO3 edge ignored - not held (50ms); likely crosstalk
```

**Require a deliberate hold for anything destructive.** The shipped config
gives shutdown 1.5 seconds:

```bash
REC_GPIO_BUTTONS=(
    "3@1500:sudo shutdown now"              # press and hold
    "4:bash $REC_BIN/stop_current_ui.sh"    # default 50 ms
)
```

**If it still happens**, the remaining fixes are electrical:

| Fix | Why |
|---|---|
| **10 kΩ pull-up** from the pin to 3.3 V | Five times stiffer than the internal one, so a transient moves the line far less |
| **100 nF capacitor** across the switch | Shunts the transient to ground |
| **Shorter wires**, button runs kept apart | Coupling scales with length and proximity |
| **Avoid GPIO 2 and 3** for anything but power | They carry permanent on-board pull-ups and are the I²C pins — if I²C is enabled the kernel drives them too |

Raising `HOLD_MS` further (`"4@200:..."`) works as a stopgap, but it trades
responsiveness for tolerance; a pull-up resistor is the real answer.

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
