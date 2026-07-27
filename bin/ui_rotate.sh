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

# Consecutive failed starts of the current UI; used to back off rather than
# spawn an instance per cycle.
start_failures=0

# Every name a given UI might appear under: the configured process name, and
# the basename of whatever command starts it.
#
# These often differ. kodi-standalone is a script that execs kodi.bin, so the
# configured name may match nothing once it has handed over. A UI the watchdog
# cannot see is a UI it starts again - which is how you end up with five Kodis.
ui_candidates() {
    local idx="$1" start
    printf '%s\n' "${REC_UI_PROCESSES[$idx]}"
    start="${REC_UI_START[$idx]%% *}"
    printf '%s\n' "${start##*/}"
}

# Returns 0 when the UI at index $1 is alive, under any of its names.
ui_running_at() {
    local idx="$1" name
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        rec_ui_running "$name" && return 0
    done < <(ui_candidates "$idx")
    return 1
}

# Returns 0 when any configured UI is alive.
any_ui_running() {
    local i
    for i in "${!REC_UI_PROCESSES[@]}"; do
        ui_running_at "$i" && return 0
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

        # Check the binary exists before trying, so the log says something
        # useful instead of the same failure repeating forever.
        start_binary="${REC_UI_START[$index]%% *}"
        if ! rec_has "$start_binary"; then
            rec_error "Cannot start ${REC_UI_NAMES[$index]}: '$start_binary' not found on PATH."
            # It may well be installed but outside PATH - RetroPie in
            # particular lives under /opt/retropie. Say so rather than
            # asserting it is missing.
            found="$(find /opt /usr/local -maxdepth 4 -name "$start_binary" -type f 2>/dev/null | head -1)"
            if [[ -n "$found" ]]; then
                rec_error "It does exist at: $found"
                rec_error "Use that absolute path in REC_UI_START in config.sh."
            else
                rec_error "Either install it, or remove index $index from all four"
                rec_error "REC_UI_* arrays in config.sh - see docs/50-ui-rotation.md."
            fi
            # Fall back to the default UI rather than retrying something that
            # cannot work, so the TV does not sit black forever.
            if (( index != REC_UI_DEFAULT_INDEX )); then
                rec_warn "Falling back to ${REC_UI_NAMES[$REC_UI_DEFAULT_INDEX]}."
                echo "$REC_UI_DEFAULT_INDEX" > "$REC_UI_STATE_FILE"
            else
                sleep 30
            fi
            continue
        fi

        # Refuse to pile up instances. If anything matching this UI is already
        # running we must not start another, however the detection got here.
        if ui_running_at "$index"; then
            rec_warn "${REC_UI_NAMES[$index]} already appears to be running - not starting another."
            sleep 5
            continue
        fi

        rec_log "No UI running. Starting ${REC_UI_NAMES[$index]}: ${REC_UI_START[$index]}"
        eval "${REC_UI_START[$index]}"

        # Give the UI time to claim the framebuffer before polling again,
        # otherwise a slow-starting Kodi gets started a second time.
        sleep 10

        if ui_running_at "$index"; then
            start_failures=0
        else
            start_failures=$((start_failures + 1))
            rec_warn "${REC_UI_NAMES[$index]} did not appear under any of: $(ui_candidates "$index" | tr '\n' ' ')"
            rec_warn "Either it failed to start, or REC_UI_PROCESSES has the wrong name."
            rec_warn "Check with: ps -A | grep -i ${REC_UI_PROCESSES[$index]:0:6}"

            # Back off hard rather than spawning a new instance every cycle -
            # that is how a single undetectable UI became five running copies.
            if (( start_failures >= 3 )); then
                rec_error "${REC_UI_NAMES[$index]} failed to start $start_failures times."
                rec_error "Pausing for 5 minutes instead of launching more copies."
                rec_error "Fix config.sh, then: pkill -f ui_rotate.sh (autostart restarts it)"
                sleep 300
                start_failures=0
            else
                sleep 20
            fi
        fi
    fi
    sleep 1
done
