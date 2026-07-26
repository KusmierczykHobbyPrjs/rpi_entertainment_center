#!/bin/bash
# ---------------------------------------------------------------------------
# stop_current_ui.sh - switch to the next UI.
#
# Stops whichever UI is running and records which one ui_rotate.sh should
# start next. Bound to a physical GPIO button (see config.sh) and available
# from Kodi through the Shell Script Launcher add-on.
#
#   stop_current_ui.sh          switch to the NEXT UI
#   stop_current_ui.sh prev     switch to the PREVIOUS UI
#
# See docs/50-ui-rotation.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

REC_UI_STATE_FILE="/tmp/rec-next-ui-index"

# A physical button bounces; ignore presses closer together than 5 seconds.
rec_rate_limit 5

# Audible confirmation that the press was registered - the UI takes several
# seconds to change, and without this the button feels broken.
bash "$REC_BIN/signal_action.sh" &

# Find which UI is currently running.
current_index=-1
for i in "${!REC_UI_PROCESSES[@]}"; do
    if pgrep -x "${REC_UI_PROCESSES[$i]}" >/dev/null 2>&1; then
        current_index=$i
        break
    fi
done

if (( current_index == -1 )); then
    rec_warn "No running UI found. Letting the watchdog start the default."
    rm -f "$REC_UI_STATE_FILE"
    exit 0
fi

# Work out where to go next.
count=${#REC_UI_PROCESSES[@]}
if [[ "${1:-}" == "prev" ]]; then
    next_index=$(( (current_index - 1 + count) % count ))
else
    next_index=$(( (current_index + 1) % count ))
fi

# Record the target BEFORE killing the current UI, so that ui_rotate.sh always
# finds a valid choice even if this script is interrupted mid-way.
echo "$next_index" > "$REC_UI_STATE_FILE"
rec_log "Next UI will be ${REC_UI_NAMES[$next_index]}"

rec_log "Stopping ${REC_UI_NAMES[$current_index]}: ${REC_UI_STOP[$current_index]}"
eval "${REC_UI_STOP[$current_index]}"

# Kodi's clean "Quit" can take a few seconds. If it is still alive after the
# grace period, escalate - otherwise the watchdog sees a UI running and never
# starts the next one, which looks like the button did nothing.
for _ in {1..10}; do
    pgrep -x "${REC_UI_PROCESSES[$current_index]}" >/dev/null 2>&1 || exit 0
    sleep 1
done

rec_warn "${REC_UI_NAMES[$current_index]} did not exit cleanly - forcing."
pkill -x "${REC_UI_PROCESSES[$current_index]}" 2>/dev/null
sleep 2
pkill -9 -x "${REC_UI_PROCESSES[$current_index]}" 2>/dev/null
