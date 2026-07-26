#!/bin/bash
# ---------------------------------------------------------------------------
# nordvpn_rotate.sh - move to the next entry in $NORDVPN_COUNTRIES.
#
# This is the one-button VPN control: each press advances through the list of
# countries in config.sh and wraps around. The pseudo-country "xx" means
# "disconnected", so putting it in the list gives you a no-VPN position.
#
# Bound to a GPIO button and to a Kodi Shell Script Launcher entry.
# See docs/70-nordvpn.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

# Button debounce: reconnecting takes several seconds, and queueing up presses
# leaves the daemon in a confused state.
rec_rate_limit 5

rec_has nordvpn || rec_die "nordvpn is not installed. See docs/70-nordvpn.md."

read -r -a countries <<<"${NORDVPN_COUNTRIES:-xx us de fr}"
(( ${#countries[@]} > 0 )) || rec_die "NORDVPN_COUNTRIES is empty in config.sh."

# Identify the current position from the server hostname, e.g. "pl123" -> pl.
# A disconnected tunnel has no hostname and maps to the sentinel "xx".
current_hostname="$(nordvpn status 2>/dev/null | grep -oP 'Hostname:\s*\K\S*' || true)"
if [[ "$current_hostname" =~ ^([a-z]{2}) ]]; then
    current_code="${BASH_REMATCH[1]}"
else
    current_code="xx"
fi

# Find the entry after the current one, wrapping to the start of the list.
# Entries may pin a server number (uk2431); match on the two-letter prefix.
next_country="${countries[0]}"
for i in "${!countries[@]}"; do
    entry="${countries[$i]}"
    if [[ "${entry:0:2}" == "$current_code" ]]; then
        next_country="${countries[$(( (i + 1) % ${#countries[@]} ))]}"
        break
    fi
done

bash "$REC_BIN/signal_action.sh" &

if [[ "$next_country" == "xx" ]]; then
    rec_log "Disconnecting VPN."
    nordvpn disconnect
else
    rec_log "Connecting VPN to $next_country."
    nordvpn connect "$next_country"
fi
