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
# Run in the foreground by bin/autostart.sh, on the console, so that the TV
# shows what is happening instead of an empty prompt. Runs forever.
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

        # Strip the trailing '&'. REC_UI_START has carried one since the
        # watchdog started UIs as detached background jobs; leaving it would
        # detach this one too, which is exactly what left the console blank and
        # meant the only way to know the UI had exited was to poll `ps`.
        start_cmd="$(sed 's/[[:space:]]*&[[:space:]]*$//' <<<"${REC_UI_START[$index]}")"

        echo
        rec_log "Starting ${REC_UI_NAMES[$index]}"
        rec_log "  command: $start_cmd"
        rec_log "  switch UI: press the button, or run bin/stop_current_ui.sh"
        echo

        # Run it HERE, in the foreground, on this terminal. The UI's own output
        # lands on the console, and this returns the moment the UI exits -
        # no polling, and no way to start a second copy of something already
        # running, because this loop cannot reach the top until it is gone.
        started_at=$SECONDS
        eval "$start_cmd"
        ran_for=$(( SECONDS - started_at ))

        echo
        rec_log "${REC_UI_NAMES[$index]} exited after ${ran_for}s."

        # Was that a failure, or did somebody just press the switch button?
        #
        # Duration alone cannot tell them apart: switching two seconds after a
        # UI appears is perfectly normal, and counting it as a failed start
        # would pause the watchdog for five minutes after three quick presses -
        # a switch button that stops working is exactly the bug this file
        # already warns about elsewhere.
        #
        # stop_current_ui.sh records the UI to go to BEFORE stopping the
        # current one, so a recorded index that is not the one that just ran is
        # positive evidence the exit was deliberate.
        switched=0
        if [[ -f "$REC_UI_STATE_FILE" ]]; then
            requested="$(cat "$REC_UI_STATE_FILE" 2>/dev/null)"
            [[ -n "$requested" && "$requested" != "$index" ]] && switched=1
        fi

        if (( ran_for >= 5 || switched )); then
            start_failures=0
        else
            start_failures=$((start_failures + 1))
            rec_warn "${REC_UI_NAMES[$index]} exited immediately - it probably failed to start."
            rec_warn "Run it by hand to see why: $start_cmd"

            # Back off rather than relaunching every second, which would fill
            # the screen with the same failure and hide the reason for it.
            if (( start_failures >= 3 )); then
                rec_error "${REC_UI_NAMES[$index]} failed to start $start_failures times."
                rec_error "Pausing for 5 minutes instead of retrying in a tight loop."
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
