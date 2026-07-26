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

# Milliseconds of hardware debounce. Mechanical buttons bounce for a few
# milliseconds; without this a single press fires several times.
BOUNCE_MS = 300

# Seconds of software debounce on top of the hardware setting. Actions here
# are heavyweight (shutdown, UI switch, VPN reconnect), so a second press
# within this window is almost always an accident.
REPEAT_GUARD_S = 1.0


def parse_button(spec):
    """Turn "17:bash foo.sh --flag" into (17, ["bash", "foo.sh", "--flag"])."""
    pin_text, _, command_text = spec.partition(":")
    if not command_text.strip():
        raise ValueError(f"missing command in {spec!r} (expected 'PIN:COMMAND')")
    try:
        pin = int(pin_text.strip())
    except ValueError:
        raise ValueError(f"invalid BCM pin number in {spec!r}") from None
    return pin, shlex.split(command_text)


def make_handler(pin, command):
    """Build the edge callback for one button, with its own repeat guard."""
    state = {"last": 0.0}

    def handler(_channel):
        now = time.monotonic()
        if now - state["last"] < REPEAT_GUARD_S:
            return
        state["last"] = now

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

    for pin, command in buttons:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.add_event_detect(
            pin,
            GPIO.FALLING,
            callback=make_handler(pin, command),
            bouncetime=BOUNCE_MS,
        )
        print(f"[gpio] GPIO{pin} -> {' '.join(command)}", flush=True)

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
