#!/bin/bash
# ---------------------------------------------------------------------------
# desktop_set_resolution.sh - pin the desktop to a modest resolution.
#
# LXDE otherwise picks the highest mode the TV advertises. A Pi 3B cannot play
# 1080p video in a browser at that size, so the desktop session is pinned to
# something it can actually drive.
#
# Kodi and RetroPie are unaffected - they set their own modes - which is why
# this is done with xrandr at session start rather than globally in
# /boot/config.txt.
#
# Values come from $REC_DESKTOP_OUTPUT / _MODE / _RATE in config.sh.
# Run by the LXDE autostart file; see docs/40-desktop.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

export DISPLAY="${DISPLAY:-:0}"

rec_has xrandr || rec_die "xrandr is not installed. Run: sudo apt-get install x11-xserver-utils"

output="${REC_DESKTOP_OUTPUT:-HDMI-1}"
mode="${REC_DESKTOP_MODE:-1360x768}"
rate="${REC_DESKTOP_RATE:-60}"

# Output names differ between the Pi's display drivers (HDMI-1 vs HDMI-A-1).
# Fall back to the first connected output rather than failing outright.
if ! xrandr --query | grep -q "^${output} connected"; then
    detected="$(xrandr --query | awk '/ connected/{print $1; exit}')"
    if [[ -n "$detected" ]]; then
        rec_warn "Output '$output' not found; using detected output '$detected'."
        rec_warn "Set REC_DESKTOP_OUTPUT=$detected in config.sh to silence this."
        output="$detected"
    else
        rec_die "No connected display found. Check the HDMI cable."
    fi
fi

rec_log "Setting $output to ${mode}@${rate}Hz"
if ! xrandr --output "$output" --mode "$mode" --rate "$rate"; then
    rec_error "Mode ${mode}@${rate} was rejected. Available modes:"
    xrandr --query | sed -n "/^${output} connected/,/^[A-Za-z]/p" | sed 1d
    exit 1
fi
