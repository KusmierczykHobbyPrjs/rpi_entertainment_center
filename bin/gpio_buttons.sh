#!/bin/bash
# ---------------------------------------------------------------------------
# gpio_buttons.sh - start the physical button listener.
#
# Reads the button map from $REC_GPIO_BUTTONS in config.sh and hands it to
# gpio_buttons.py, which does the actual GPIO work.
#
# Started in the background by bin/autostart.sh.
# See docs/60-gpio.md for the wiring and docs/HARDWARE.md for the pinout.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

if ! rec_single_instance gpio_buttons; then
    exit 0
fi

if [[ ${#REC_GPIO_BUTTONS[@]} -eq 0 ]]; then
    rec_log "No buttons configured in REC_GPIO_BUTTONS - nothing to do."
    exit 0
fi

# Buttons trigger actions like `shutdown now`, so the listener needs the right
# to run them. The installer grants passwordless sudo for exactly those
# commands rather than running this whole script as root.
exec python3 "$REC_BIN/gpio_buttons.py" "${REC_GPIO_BUTTONS[@]}"
