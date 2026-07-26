#!/bin/bash
# ---------------------------------------------------------------------------
# pi_temp.sh - report CPU and GPU temperature.
#
# Worth checking after any change to the case or to video settings: a Pi 3B
# throttles at 80 C, which shows up as stuttering video and slow emulation
# rather than as an error message anywhere.
# ---------------------------------------------------------------------------
set -uo pipefail

cpu_millicelsius="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)"
cpu_celsius=$(( cpu_millicelsius / 1000 ))

echo "$(date) @ $(hostname)"
echo "-------------------------------------------"
if command -v vcgencmd >/dev/null 2>&1; then
    echo "GPU => $(vcgencmd measure_temp | cut -d= -f2)"
    # Non-zero throttling bits mean the Pi has already been slowed down,
    # either now or at some point since boot.
    throttled="$(vcgencmd get_throttled | cut -d= -f2)"
    echo "Throttling flags => $throttled"
    if [[ "$throttled" != "0x0" ]]; then
        echo "  (non-zero: under-voltage or over-temperature has occurred;"
        echo "   check the power supply and cooling - see docs/TROUBLESHOOTING.md)"
    fi
fi
echo "CPU => ${cpu_celsius}'C"
