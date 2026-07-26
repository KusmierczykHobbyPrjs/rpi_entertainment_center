#!/bin/bash
# ---------------------------------------------------------------------------
# chromium_kill.sh - close Chromium and forget the session.
#
# Clearing the session data matters here: without it Chromium reopens the last
# set of tabs (and its "didn't shut down correctly" bar) the next time
# clipboard2chromium.sh launches it, which on a TV means a restore prompt
# nobody can dismiss without a keyboard.
#
# See docs/45-kdeconnect.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

# The binary is chromium-browser on Raspberry Pi OS and chromium elsewhere.
if ! pgrep -f "chromium" >/dev/null 2>&1; then
    rec_log "Chromium is not running."
    exit 0
fi

rec_log "Stopping Chromium."
pkill -f "chromium-browser" 2>/dev/null
pkill -f "chromium"         2>/dev/null

# Wait for a clean exit, escalating to SIGKILL if it hangs.
for i in {1..10}; do
    pgrep -f "chromium" >/dev/null 2>&1 || break
    if (( i == 5 )); then
        rec_warn "Chromium is not responding - forcing."
        pkill -9 -f "chromium-browser" 2>/dev/null
        pkill -9 -f "chromium"         2>/dev/null
    fi
    sleep 0.3
done

rec_log "Clearing Chromium session data."
profile="$HOME/.config/chromium/Default"
rm -f "$profile"/Sessions/*   2>/dev/null
rm -f "$profile"/Session*     2>/dev/null
rm -f "$profile"/Current*     2>/dev/null

# Preferences carries the "exit_type" flag that triggers the restore prompt.
# Rewrite that one field instead of deleting the whole file, which would also
# throw away zoom levels, permissions and the chosen language.
if [[ -f "$profile/Preferences" ]] && rec_has python3; then
    python3 - "$profile/Preferences" <<'PY' 2>/dev/null || true
import json, sys
path = sys.argv[1]
with open(path) as fh:
    prefs = json.load(fh)
prefs.setdefault("profile", {})["exit_type"] = "Normal"
prefs["profile"]["exited_cleanly"] = True
with open(path, "w") as fh:
    json.dump(prefs, fh)
PY
fi

rec_log "Chromium stopped and session cleared."
