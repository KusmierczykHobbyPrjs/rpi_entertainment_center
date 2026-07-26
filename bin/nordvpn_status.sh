#!/bin/bash
# ---------------------------------------------------------------------------
# nordvpn_status.sh - speak the current VPN status.
#
# Used by the Kodi Shell Script Launcher menu, where there is no console to
# read the output from.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

rec_has nordvpn || rec_die "nordvpn is not installed. See docs/70-nordvpn.md."

status="$(nordvpn status 2>/dev/null)"

if grep -q "Status: Connected" <<<"$status"; then
    country="$(grep -i '^ *Country:' <<<"$status" | cut -d: -f2- | xargs)"
    city="$(   grep -i '^ *City:'    <<<"$status" | cut -d: -f2- | xargs)"
    message="VPN is connected to $city, $country"
else
    message="VPN is disconnected"
fi

# Print for the console/log as well as speaking, so the same script is useful
# over SSH.
rec_log "$message"
bash "$REC_BIN/speech.sh" "$message"
