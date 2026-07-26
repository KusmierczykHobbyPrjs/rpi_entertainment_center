#!/bin/bash
# ---------------------------------------------------------------------------
# clipboard2chromium.sh - open the clipboard URL full-screen on the TV.
#
# The intended flow, from the sofa, with only a phone:
#   1. copy a URL on your phone
#   2. KDE Connect -> "Send clipboard"
#   3. KDE Connect -> Run command -> "Open clipboard URL"
#
# This is how web-only players (ones with no Kodi add-on) get watched on the
# TV. Registered as a KDE Connect command by the installer.
#
# See docs/45-kdeconnect.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

rec_has xclip || rec_die "xclip is not installed. Run: sudo apt-get install xclip"

# KDE Connect runs commands without a DISPLAY, so point at the desktop session
# explicitly or Chromium has nowhere to draw.
export DISPLAY="${DISPLAY:-:0}"

bash "$REC_BIN/signal_action.sh" &

URL="$(xclip -selection clipboard -o 2>/dev/null)"

if [[ -z "$URL" ]]; then
    rec_error "Clipboard is empty. Send the clipboard from your phone first."
    exit 1
fi

# Only ever hand a real URL to the browser - a stray clipboard containing
# shell-ish text should not become a search or a local file open.
if [[ ! "$URL" =~ ^https?:// ]]; then
    rec_error "Clipboard does not contain an http(s) URL: ${URL:0:60}"
    exit 1
fi

rec_log "Opening: $URL"

bash "$REC_BIN/chromium_kill.sh"

# Pick whichever binary this release ships.
if rec_has chromium-browser; then
    BROWSER=chromium-browser
elif rec_has chromium; then
    BROWSER=chromium
else
    rec_die "Chromium is not installed. Run: sudo apt-get install chromium-browser"
fi

# --start-fullscreen         fill the TV screen
# --noerrdialogs             never block on a modal the remote cannot dismiss
# --disable-session-crashed-bubble  no "restore pages?" bar
exec "$BROWSER" \
    --start-fullscreen \
    --noerrdialogs \
    --disable-session-crashed-bubble \
    --disable-infobars \
    "$URL"
