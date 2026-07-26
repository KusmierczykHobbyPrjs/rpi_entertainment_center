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

step "Installing the GPIO library"
# python3-rpi.gpio is the packaged version; installing it with apt rather than
# pip keeps it working after a system Python upgrade.
apt_install python3-rpi.gpio || exit 1

step "Checking the configured buttons"
if [[ ${#REC_GPIO_BUTTONS[@]} -eq 0 ]]; then
    skip "No buttons configured in REC_GPIO_BUTTONS"
else
    for entry in "${REC_GPIO_BUTTONS[@]}"; do
        pin="${entry%%:*}"
        cmd="${entry#*:}"
        if [[ "$pin" =~ ^[0-9]+$ ]]; then
            ok "GPIO$pin -> $cmd"
        else
            fail "Malformed entry (want 'PIN:COMMAND'): $entry"
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
    if id -nG "$USER" | grep -qw gpio; then
        ok "$USER is in the 'gpio' group"
    else
        sudo usermod -a -G gpio "$USER"
        ok "Added $USER to the 'gpio' group (takes effect after the next login)"
    fi
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
