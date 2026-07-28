#!/bin/bash
# ---------------------------------------------------------------------------
# 60-gpio - physical buttons.
#
# Buttons wired between a GPIO pin and ground let the Pi be used with no
# remote at all: switch UI, rotate the VPN, play/pause, shut down. This is
# also the only safe way to power the Pi off when it is showing a game.
#
# See docs/60-gpio.md for what each button does and docs/HARDWARE.md for the
# wiring diagram.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"
rec_load_config

require_not_root
warn_if_not_pi

step "Checking the GPIO library"
# Two packages provide the RPi.GPIO module and they CONFLICT - installing one
# makes apt remove the other:
#
#   python3-rpi.gpio    the original. Talks to the hardware registers directly.
#                       Works on Pi 2/3/4/Zero; does NOT work on a Pi 5, whose
#                       RP1 chip needs different drivers.
#   python3-rpi-lgpio   a drop-in replacement over lgpio, using the modern
#                       character-device interface. Shipped by default on
#                       Bookworm and later, and the only option on a Pi 5.
#
# So: if the module already imports, leave well alone. An earlier version of
# this installer unconditionally installed python3-rpi.gpio, which silently
# uninstalled the OS-provided python3-rpi-lgpio.
if python3 -c "import RPi.GPIO" 2>/dev/null; then
    provider="$(dpkg -S "$(python3 -c 'import RPi.GPIO, os; print(os.path.dirname(RPi.GPIO.__file__))' 2>/dev/null)" 2>/dev/null | cut -d: -f1 | head -1)"
    ok "RPi.GPIO is available${provider:+ (from $provider)}"
    skip "Not installing anything - the two providers conflict"
else
    # Nothing provides it. Pick the right one for this hardware.
    pi_model="$( { tr -d '\0' < /proc/device-tree/model; } 2>/dev/null )"
    if [[ "$pi_model" == *"Pi 5"* ]]; then
        note "Raspberry Pi 5 detected - the original RPi.GPIO does not work here"
        apt_install python3-rpi-lgpio || exit 1
    elif grep -qE '^VERSION_ID="1[2-9]"' /etc/os-release 2>/dev/null; then
        note "Bookworm or later - preferring the lgpio-backed drop-in"
        apt_install python3-rpi-lgpio || apt_install python3-rpi.gpio || exit 1
    else
        apt_install python3-rpi.gpio || exit 1
    fi
fi

step "Checking the configured buttons"
if [[ ${#REC_GPIO_BUTTONS[@]} -eq 0 ]]; then
    skip "No buttons configured in REC_GPIO_BUTTONS"
else
    for entry in "${REC_GPIO_BUTTONS[@]}"; do
        if rec_parse_button "$entry"; then
            ok "GPIO$REC_BTN_PIN (hold ${REC_BTN_HOLD_MS}ms) -> $REC_BTN_CMD"
            if rec_button_is_destructive "$REC_BTN_CMD" && (( REC_BTN_HOLD_MS < 1000 )); then
                note "GPIO$REC_BTN_PIN powers the Pi down after only ${REC_BTN_HOLD_MS}ms."
                note "Crosstalk from a neighbouring button can trigger that."
                note "Consider \"${REC_BTN_PIN}@1500:${REC_BTN_CMD}\" - see docs/60-gpio.md."
            fi
        else
            fail "Malformed entry (want 'PIN:COMMAND' or 'PIN@HOLD_MS:COMMAND'): $entry"
        fi
    done
fi

step "Granting passwordless shutdown"
# The shutdown button runs as the normal user. Rather than running the whole
# GPIO listener as root, allow exactly the two power commands without a
# password - a button press has no way to type one.
SUDOERS_FILE="/etc/sudoers.d/010_rec-gpio-power"
SUDOERS_LINE="$USER ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /usr/sbin/shutdown, /usr/sbin/reboot"

if sudo test -f "$SUDOERS_FILE" && sudo grep -qF "$SUDOERS_LINE" "$SUDOERS_FILE"; then
    skip "Passwordless shutdown already configured"
else
    # Write to a temporary file and validate it before installing. A syntax
    # error in a sudoers file can lock you out of sudo entirely.
    tmp="$(mktemp)"
    printf '# Installed by rpi-entertainment-center (module 60-gpio).\n' > "$tmp"
    printf '# Lets the GPIO power button shut the Pi down without a password.\n' >> "$tmp"
    printf '%s\n' "$SUDOERS_LINE" >> "$tmp"

    if sudo visudo -c -f "$tmp" >/dev/null 2>&1; then
        sudo install -m 0440 -o root -g root "$tmp" "$SUDOERS_FILE"
        ok "Installed $SUDOERS_FILE"
    else
        fail "Generated sudoers file failed validation - not installing it."
        fail "The shutdown button will not work until this is fixed."
    fi
    rm -f "$tmp"
fi

step "Checking GPIO access"
if [[ -e /dev/gpiomem ]]; then
    ensure_group gpio || true
else
    skip "/dev/gpiomem not present - not a Raspberry Pi, or GPIO is disabled"
fi

echo
ok "GPIO buttons configured."
cat <<EOF

${REC_C_BOLD}Wiring${REC_C_OFF}

Each button connects its GPIO pin to any ground pin. Nothing else is needed:
the script enables the Pi's internal pull-up resistor, so the pin idles high
and a press pulls it low.

    GPIO pin ----o  o---- GND
                button

${REC_C_BOLD}Default button map${REC_C_OFF} (change it in config.sh)

    GPIO 3   power off          (also wakes the Pi from halt - see below)
    GPIO 4   switch UI
    GPIO 17  next VPN country
    GPIO 22  play / pause
    GPIO 27  play radio

GPIO 3 is deliberately chosen for power: it is the only pin that also powers
the Pi back on after a shutdown, so one button does both.

${REC_C_BOLD}Testing${REC_C_OFF}

Run the listener in the foreground and press each button:

    python3 $REC_BIN/gpio_buttons.py "4:echo BUTTON-4-WORKS"

See docs/HARDWARE.md for the full pinout and a photo of the finished build.
EOF
