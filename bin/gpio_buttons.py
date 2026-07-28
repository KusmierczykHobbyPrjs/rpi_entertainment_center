#!/usr/bin/env python3
"""Run shell commands when physical GPIO buttons are pressed.

Each argument is a "PIN:COMMAND" pair, where PIN is a BCM pin number and
COMMAND is a shell command line:

    gpio_buttons.py "3:shutdown now" "4:bash /path/to/stop_current_ui.sh"

Buttons are wired between the pin and ground; the internal pull-up resistor is
enabled, so pressing a button pulls the pin low and we trigger on the falling
edge. See docs/HARDWARE.md for the wiring diagram.

One process handles every button. The previous design started a separate
Python interpreter per pin, which cost roughly 10 MB of RAM each - noticeable
on a Pi 3B with 1 GB shared with the GPU.
"""

import shlex
import subprocess
import sys
import time

try:
    import RPi.GPIO as GPIO
except ImportError:
    sys.exit(
        "RPi.GPIO is not available.\n"
        "Install it with: sudo apt-get install python3-rpi.gpio"
    )

# Which package is providing RPi.GPIO? The two behave differently in a way that
# matters here, and importing the shim pulls lgpio in with it.
ON_LGPIO = "lgpio" in sys.modules

# Milliseconds of debounce. Mechanical contacts bounce for a few milliseconds;
# without this a single press fires several times.
#
# THE TWO BACKENDS INTERPRET THIS COMPLETELY DIFFERENTLY:
#
#   python3-rpi.gpio    A lockout. The first edge is reported immediately, then
#                       further edges are ignored for BOUNCE_MS. Costs nothing
#                       in latency, so it can afford to be generous.
#
#   python3-rpi-lgpio   A stability filter. The line must stay steady for
#                       BOUNCE_MS before the edge is reported AT ALL - so this
#                       value is added directly to how long you must hold the
#                       button before anything happens.
#
# 300 ms on the shim therefore means every press needs a third of a second of
# steady contact before the callback even runs, on top of the hold check below.
# That reads as "the buttons have stopped working". rpi-lgpio's own
# documentation says as much: "you may find shorter debounce periods preferable
# when working with rpi-lgpio".
#
# 20 ms is still far longer than contact bounce or any crosstalk transient.
BOUNCE_MS = 20 if ON_LGPIO else 300

# Seconds of software debounce on top of the hardware setting. Actions here
# are heavyweight (shutdown, UI switch, VPN reconnect), so a second press
# within this window is almost always an accident.
REPEAT_GUARD_S = 1.0

# Milliseconds the pin must STAY low before we believe it.
#
# An edge alone is not a press. The internal pull-ups are weak (~50k), header
# pins are physically adjacent, and button wiring is usually unshielded - so
# pressing one button couples a transient into its neighbours and produces a
# perfectly real falling edge on a pin nobody touched. Acting on the edge
# alone made other buttons fire, most alarmingly the shutdown one.
#
# Re-reading after a short settle rejects those: a genuine press holds the pin
# low for tens of milliseconds at least, a crosstalk glitch does not.
DEFAULT_HOLD_MS = 50


def parse_button(spec):
    """Parse a button spec into (pin, hold_ms, command).

    Accepted forms:
        "17:bash foo.sh"        hold for DEFAULT_HOLD_MS
        "3@1500:sudo shutdown"  hold the pin low for 1500 ms first

    The @HOLD suffix is optional, so existing "PIN:COMMAND" entries keep
    working unchanged. It is worth using on destructive actions: requiring a
    deliberate press makes an accidental shutdown far less likely.
    """
    pin_text, _, command_text = spec.partition(":")
    if not command_text.strip():
        raise ValueError(f"missing command in {spec!r} (expected 'PIN:COMMAND')")

    hold_ms = DEFAULT_HOLD_MS
    if "@" in pin_text:
        pin_text, _, hold_text = pin_text.partition("@")
        try:
            hold_ms = int(hold_text.strip())
        except ValueError:
            raise ValueError(f"invalid hold time in {spec!r}") from None

    try:
        pin = int(pin_text.strip())
    except ValueError:
        raise ValueError(f"invalid BCM pin number in {spec!r}") from None
    return pin, hold_ms, shlex.split(command_text)


def hold_remaining_ms(hold_ms):
    """How much longer we must watch the pin ourselves.

    HOLD_MS means "the pin must stay low this long before the press counts",
    measured from the moment contact is made. On rpi-lgpio the debounce filter
    has already waited BOUNCE_MS of steady signal before telling us anything,
    so that time is served - counting it again would make "3@1500" mean 1800 ms
    and every ordinary button 50 ms slower than configured.
    """
    if ON_LGPIO:
        return max(0, hold_ms - BOUNCE_MS)
    return hold_ms


def make_handler(pin, hold_ms, command):
    """Build the edge callback for one button, with its own repeat guard."""
    state = {"last": 0.0}
    remaining_ms = hold_remaining_ms(hold_ms)

    def handler(_channel):
        now = time.monotonic()
        if now - state["last"] < REPEAT_GUARD_S:
            # Logged rather than silent: an ignored press is indistinguishable
            # from a dead button when you are standing in front of the TV.
            print(f"[gpio] GPIO{pin} ignored - within {REPEAT_GUARD_S}s of the "
                  f"last press", flush=True)
            return

        # Confirm the press is real. Buttons pull the pin to ground, so a held
        # button reads LOW throughout; a crosstalk transient has already gone.
        deadline = now + (remaining_ms / 1000.0)
        while time.monotonic() < deadline:
            if GPIO.input(pin) != GPIO.LOW:
                print(f"[gpio] GPIO{pin} edge ignored - not held "
                      f"({hold_ms}ms); likely crosstalk", flush=True)
                return
            time.sleep(0.005)

        state["last"] = time.monotonic()
        print(f"[gpio] GPIO{pin} pressed -> {' '.join(command)}", flush=True)
        try:
            # shell=False: the command was already tokenised by shlex, so a
            # stray character in config.sh cannot turn into shell injection.
            subprocess.Popen(command)
        except Exception as exc:  # noqa: BLE001 - must never kill the listener
            print(f"[gpio] GPIO{pin} command failed: {exc}", file=sys.stderr, flush=True)

    return handler


def main(argv):
    if not argv:
        print(__doc__)
        return 1

    try:
        buttons = [parse_button(spec) for spec in argv]
    except ValueError as exc:
        print(f"[gpio] Configuration error: {exc}", file=sys.stderr)
        return 1

    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)

    backend = "rpi-lgpio" if ON_LGPIO else "RPi.GPIO"
    print(f"[gpio] Backend: {backend}, debounce {BOUNCE_MS}ms", flush=True)

    for pin, hold_ms, command in buttons:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.add_event_detect(
            pin,
            GPIO.FALLING,
            callback=make_handler(pin, hold_ms, command),
            bouncetime=BOUNCE_MS,
        )
        # Print the time you actually have to hold the button, not the
        # configured number - on rpi-lgpio part of it is served by the
        # debounce filter, and the difference used to be a third of a second.
        press_ms = max(hold_ms, BOUNCE_MS) if ON_LGPIO else hold_ms
        print(f"[gpio] GPIO{pin} -> {' '.join(command)}   "
              f"(press and hold ~{press_ms}ms)", flush=True)

    print(f"[gpio] Listening on {len(buttons)} button(s). Ctrl-C to stop.", flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
    finally:
        GPIO.cleanup()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
