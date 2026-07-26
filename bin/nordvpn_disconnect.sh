#!/bin/bash
# ---------------------------------------------------------------------------
# nordvpn_disconnect.sh - drop the VPN tunnel.
#
# Used by the Kodi Shell Script Launcher menu.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

rec_has nordvpn || rec_die "nordvpn is not installed. See docs/70-nordvpn.md."

bash "$REC_BIN/signal_action.sh" &

rec_log "Disconnecting VPN"
nordvpn disconnect
