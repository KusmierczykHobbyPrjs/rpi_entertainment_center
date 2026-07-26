#!/bin/bash
# ---------------------------------------------------------------------------
# autostart.sh - start every background service this project needs.
#
# Launched at boot from ~/.bashrc, which the Pi runs because raspi-config is
# set to "Console Autologin". Console autologin (rather than desktop
# autologin) is what lets this script decide which UI comes up.
#
# Everything it does is written to $REC_LOG, because this runs before any
# terminal you can watch and silent failure here looks exactly like "nothing
# works". Check it with:
#
#     bin/doctor.sh autostart
#     cat ~/.local/state/rec/autostart.log
#
# See docs/50-ui-rotation.md and docs/TROUBLESHOOTING.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

REC_LOG_DIR="$HOME/.local/state/rec"
REC_LOG="$REC_LOG_DIR/autostart.log"
mkdir -p "$REC_LOG_DIR" 2>/dev/null

# Keep the log from growing without bound across reboots.
if [[ -f "$REC_LOG" ]] && [[ $(stat -c%s "$REC_LOG" 2>/dev/null || echo 0) -gt 262144 ]]; then
    tail -c 65536 "$REC_LOG" > "$REC_LOG.tmp" && mv "$REC_LOG.tmp" "$REC_LOG"
fi

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$REC_LOG"; }

log "--- autostart invoked on $(tty 2>/dev/null || echo 'no tty') (pid $$) ---"

# .bashrc runs for every interactive shell, including each SSH login. Starting
# the UI watchdog from an SSH session would fight the console session for the
# screen, so only the physical console proceeds.
# Set REC_FORCE_AUTOSTART=1 to override (useful when testing).
if [[ "${REC_FORCE_AUTOSTART:-0}" != "1" ]]; then
    current_tty="$(tty 2>/dev/null || echo '')"
    case "$current_tty" in
        /dev/tty1) log "On the console - proceeding." ;;
        *)
            log "Not the console (tty='$current_tty') - exiting without starting anything."
            log "This is normal for SSH. If you see this on the TV, the Pi is not"
            log "booting to a console: check 'systemctl get-default' is multi-user.target."
            exit 0
            ;;
    esac
else
    log "REC_FORCE_AUTOSTART=1 - proceeding regardless of tty."
fi

log "Repository: $REC_ROOT"
log "Config:     $([[ -f "$REC_ROOT/config.sh" ]] && echo present || echo MISSING)"
log "UIs:        ${REC_UI_NAMES[*]:-none configured}"

# Start one background service, recording whether its script even exists.
start_service() {
    local label="$1" script="$2"
    shift 2
    if [[ ! -f "$script" ]]; then
        log "SKIP $label - $script not found"
        return
    fi
    log "START $label"
    bash "$script" "$@" >>"$REC_LOG" 2>&1 &
}

start_service "UI watchdog"      "$REC_BIN/ui_rotate.sh"
start_service "NordVPN autostart" "$REC_BIN/nordvpn_autostart.sh"
start_service "NordVPN monitor"   "$REC_BIN/nordvpn_monitor.sh"
start_service "Port forwarding"   "$REC_BIN/port_forwarding.sh"
start_service "GPIO buttons"      "$REC_BIN/gpio_buttons.sh"

log "All services launched; waiting."
wait
