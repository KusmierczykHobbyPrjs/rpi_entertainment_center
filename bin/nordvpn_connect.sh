#!/bin/bash
# ---------------------------------------------------------------------------
# nordvpn_connect.sh - connect to a named country or server.
#
#   nordvpn_connect.sh pl        connect to Poland
#   nordvpn_connect.sh uk2431    connect to a specific server
#   nordvpn_connect.sh           connect to the fastest server
#
# Used by the Kodi Shell Script Launcher menu (assets/kodi/shell_command_launcher.menu).
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

rec_has nordvpn || rec_die "nordvpn is not installed. See docs/70-nordvpn.md."

bash "$REC_BIN/signal_action.sh" &

if [[ $# -gt 0 ]]; then
    rec_log "Connecting to $1"
    nordvpn connect "$1"
else
    rec_log "Connecting to the fastest available server"
    nordvpn connect
fi
