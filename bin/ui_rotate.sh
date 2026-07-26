#!/bin/bash
# ---------------------------------------------------------------------------
# ui_rotate.sh - the UI watchdog.
#
# Exactly one UI (Kodi / EmulationStation / Desktop) should be running at any
# time. This script watches for "no UI is running" and starts the one that
# stop_current_ui.sh selected - or the configured default on first boot.
#
# Together the two scripts implement UI switching with a single button:
#   stop_current_ui.sh   kills the running UI and records which comes next
#   ui_rotate.sh         notices nothing is running and starts that one
#
# Started in the background by bin/autostart.sh. Runs forever.
# See docs/50-ui-rotation.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

# The file stop_current_ui.sh writes the next UI's array index into.
REC_UI_STATE_FILE="/tmp/rec-next-ui-index"

# Only one watchdog may run. .bashrc starts autostart.sh on every login,
# including SSH sessions, so this guard is load-bearing.
if ! rec_single_instance ui_rotate; then
    rec_log "Another ui_rotate.sh is already running - exiting."
    exit 0
fi

rec_log "UI watchdog started. Managing: ${REC_UI_NAMES[*]}"

# Returns 0 when any configured UI process is alive.
any_ui_running() {
    local proc
    for proc in "${REC_UI_PROCESSES[@]}"; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

while true; do
    if ! any_ui_running; then
        # Pick the UI to start: the one stop_current_ui.sh chose, else default.
        index="${REC_UI_DEFAULT_INDEX:-0}"
        if [[ -f "$REC_UI_STATE_FILE" ]]; then
            index="$(cat "$REC_UI_STATE_FILE" 2>/dev/null || echo "$index")"
        fi

        # Guard against a corrupt or out-of-range state file, which would
        # otherwise leave the system with no UI at all.
        if ! [[ "$index" =~ ^[0-9]+$ ]] || (( index >= ${#REC_UI_START[@]} )); then
            rec_warn "Invalid UI index '$index' - falling back to default."
            index="${REC_UI_DEFAULT_INDEX:-0}"
        fi

        rec_log "No UI running. Starting ${REC_UI_NAMES[$index]}: ${REC_UI_START[$index]}"
        eval "${REC_UI_START[$index]}"

        # Give the UI time to claim the framebuffer before polling again,
        # otherwise a slow-starting Kodi gets started a second time.
        sleep 10
    fi
    sleep 1
done
