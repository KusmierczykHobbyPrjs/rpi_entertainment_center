#!/bin/bash
# ---------------------------------------------------------------------------
# desktop_set_resolution.sh - pin the desktop to a modest resolution.
#
# The desktop otherwise picks the highest mode the TV advertises. A Pi 3B
# cannot play video in a browser at 1080p, so the desktop session is pinned to
# something it can drive. Kodi and RetroPie set their own modes and are not
# affected, which is why this runs per session rather than globally in
# /boot/firmware/config.txt.
#
# Works under both X11 (xrandr) and Wayland (wlr-randr). Bookworm and later
# default to Wayland, where xrandr does not work at all.
#
# Values come from REC_DESKTOP_OUTPUT / _MODE / _RATE in config.sh.
# See docs/40-desktop.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

output="${REC_DESKTOP_OUTPUT:-}"
mode="${REC_DESKTOP_MODE:-1360x768}"
rate="${REC_DESKTOP_RATE:-60}"

# --- Wayland ---------------------------------------------------------------
if [[ -n "${WAYLAND_DISPLAY:-}" ]] || rec_has wlr-randr && ! [[ -n "${DISPLAY:-}" ]]; then
    if ! rec_has wlr-randr; then
        rec_error "This is a Wayland session but wlr-randr is not installed."
        rec_error "Run: sudo apt install wlr-randr"
        exit 1
    fi

    # wlr-randr needs to reach the compositor; without WAYLAND_DISPLAY it
    # cannot, which is the usual cause of failure when run over SSH.
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        rec_error "No WAYLAND_DISPLAY - run this from inside a desktop session."
        exit 1
    fi

    if [[ -z "$output" ]]; then
        output="$(wlr-randr 2>/dev/null | awk '/^[A-Za-z]/{print $1; exit}')"
        [[ -n "$output" ]] || rec_die "No display found. Check the HDMI cable."
        rec_log "No REC_DESKTOP_OUTPUT set; using detected output '$output'."
    fi

    rec_log "Setting $output to ${mode}@${rate}Hz (Wayland)"
    if ! wlr-randr --output "$output" --mode "${mode}@${rate}Hz"; then
        rec_error "Mode rejected. Available modes:"
        wlr-randr
        exit 1
    fi
    exit 0
fi

# --- X11 -------------------------------------------------------------------
export DISPLAY="${DISPLAY:-:0}"

rec_has xrandr || rec_die "xrandr is not installed. Run: sudo apt install x11-xserver-utils"

if ! xrandr --query >/dev/null 2>&1; then
    rec_error "Cannot reach an X display (DISPLAY=$DISPLAY)."
    rec_error "Run this from inside a desktop session, not over a plain SSH login."
    rec_error "If your desktop is Wayland, install wlr-randr instead - see docs/40-desktop.md."
    exit 1
fi

# Output names differ between drivers (HDMI-1 vs HDMI-A-1). Fall back to the
# first connected output rather than failing outright.
if [[ -z "$output" ]] || ! xrandr --query | grep -q "^${output} connected"; then
    detected="$(xrandr --query | awk '/ connected/{print $1; exit}')"
    [[ -n "$detected" ]] || rec_die "No connected display found. Check the HDMI cable."
    [[ -n "$output" ]] && rec_warn "Output '$output' not found; using '$detected'."
    rec_warn "Set REC_DESKTOP_OUTPUT=$detected in config.sh to silence this."
    output="$detected"
fi

rec_log "Setting $output to ${mode}@${rate}Hz (X11)"
if ! xrandr --output "$output" --mode "$mode" --rate "$rate"; then
    rec_error "Mode ${mode}@${rate} was rejected. Available modes:"
    xrandr --query | sed -n "/^${output} connected/,/^[A-Za-z]/p" | sed 1d
    exit 1
fi
