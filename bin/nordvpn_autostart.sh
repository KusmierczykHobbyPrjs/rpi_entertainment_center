#!/bin/bash
# ---------------------------------------------------------------------------
# nordvpn_autostart.sh - bring the VPN up at boot.
#
# Logs in with the token from config.sh, enables Meshnet (needed to reach this
# Pi from outside the LAN) and connects to the first country in
# $NORDVPN_COUNTRIES - unless that entry is "xx", which means "start with no
# VPN".
#
# Started in the background by bin/autostart.sh.
# See docs/70-nordvpn.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

rec_has nordvpn || { rec_warn "nordvpn is not installed - skipping."; exit 0; }

read -r -a countries <<<"${NORDVPN_COUNTRIES:-xx us de fr}"

# "xx" first means the user wants to boot without a tunnel.
if [[ "${countries[0]:-xx}" == "xx" ]]; then
    rec_log "First country is 'xx' - leaving the VPN disconnected at boot."
    exit 0
fi

# The daemon and the network both need to be up. autostart.sh runs from a
# login shell that can win the race against dhcpcd, so wait rather than fail.
rec_log "Waiting for network connectivity..."
for _ in {1..30}; do
    rec_online && break
    sleep 2
done
if ! rec_online; then
    rec_warn "No network after 60s - skipping VPN autostart."
    exit 0
fi

# Already connected (e.g. this script ran twice)? Nothing to do.
if nordvpn status 2>/dev/null | grep -q "Status: Connected"; then
    rec_log "VPN is already connected."
    exit 0
fi

# Log in only if we are not already logged in; repeated logins error out.
if ! nordvpn account >/dev/null 2>&1; then
    if [[ -n "${NORDVPN_TOKEN:-}" ]]; then
        rec_log "Logging in to NordVPN with the configured token."
        nordvpn login --token "$NORDVPN_TOKEN" \
            || rec_warn "Token login failed - check NORDVPN_TOKEN in config.sh."
    else
        rec_warn "Not logged in and NORDVPN_TOKEN is empty."
        rec_warn "Run 'nordvpn login' once by hand, or set the token in config.sh."
        exit 0
    fi
fi

# Keep the LAN reachable while the tunnel is up, otherwise SSH, the Kore
# remote and the port forwards all stop working the moment the VPN connects.
if [[ -n "${NORDVPN_LAN_SUBNET:-}" ]]; then
    # NordVPN 3.16+ renamed "whitelist" to "allowlist"; try the new name first.
    nordvpn allowlist add subnet "$NORDVPN_LAN_SUBNET" >/dev/null 2>&1 \
        || nordvpn whitelist add subnet "$NORDVPN_LAN_SUBNET" >/dev/null 2>&1 \
        || rec_warn "Could not add $NORDVPN_LAN_SUBNET to the NordVPN allowlist."
fi

if [[ "${NORDVPN_MESHNET:-on}" == "on" ]]; then
    nordvpn set meshnet on >/dev/null 2>&1 || rec_warn "Could not enable Meshnet."
fi

rec_log "Connecting to ${countries[0]}."
nordvpn connect "${countries[0]}"
