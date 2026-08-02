#!/bin/bash
# ---------------------------------------------------------------------------
# nordvpn_monitor.sh - announce VPN state changes out loud.
#
# The Pi is normally driven from the sofa with no shell in sight, so the only
# practical way to know the tunnel dropped is to be told. This polls the
# NordVPN daemon and speaks whenever the connection changes.
#
# Started in the background by bin/autostart.sh. Runs forever.
# See docs/70-nordvpn.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

POLL_INTERVAL=5

if ! rec_single_instance nordvpn_monitor; then
    exit 0
fi

if ! rec_has nordvpn; then
    rec_warn "nordvpn is not installed - monitor exiting."
    exit 0
fi

rec_log "Monitoring NordVPN connection state."

previous_state=""      # empty until the first successful poll
first_poll=1

while true; do
    # One call per cycle. `nordvpn status` talks to the daemon over a socket
    # and is slow enough on a Pi 3B that calling it per-field was a
    # measurable background load.
    status="$(nordvpn status 2>/dev/null)"

    country="$(grep -i '^ *Country:'  <<<"$status" | cut -d: -f2- | xargs)"
    city="$(   grep -i '^ *City:'     <<<"$status" | cut -d: -f2- | xargs)"
    hostname="$(grep -i '^ *Hostname:' <<<"$status" | cut -d: -f2- | xargs)"

    # Track the hostname as well as country/city. Rotating between two servers
    # in the same city (pl123 -> pl456) changes nothing else, and used to go
    # unreported.
    current_state="${country}|${city}|${hostname}"

    if [[ "$current_state" != "$previous_state" ]]; then
        if [[ $first_poll -eq 1 ]]; then
            # Do not narrate the state that already existed at boot.
            rec_log "Initial VPN state: ${hostname:-disconnected}"
            first_poll=0
        elif [[ -z "$hostname" ]]; then
            rec_log "VPN disconnected (was ${previous_state%%|*})."
            # Give DNS a moment to fall back to the normal resolver. Speaking
            # immediately after the tunnel drops used to fail with
            # "Temporary failure in name resolution" and stay silent.
            sleep 3
            # "en" describes the text, not a preference - see nordvpn_status.sh.
            bash "$REC_BIN/speech.sh" en "VPN got disconnected."
        else
            rec_log "VPN connected to $hostname ($city, $country)."
            bash "$REC_BIN/speech.sh" en "VPN changed to $country, $city"
        fi
        previous_state="$current_state"
    fi

    sleep "$POLL_INTERVAL"
done
