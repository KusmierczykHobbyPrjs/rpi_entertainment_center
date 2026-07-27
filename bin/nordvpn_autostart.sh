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

# "xx" first means "do not CONNECT at boot". It does not mean "do nothing":
# logging in, allowlisting the LAN and enabling Meshnet all still need to
# happen, and Meshnet in particular is how this Pi is reached remotely.
# Treating xx as "skip everything" left the client permanently logged out.
connect_at_boot=1
if [[ "${countries[0]:-xx}" == "xx" ]]; then
    connect_at_boot=0
    rec_log "First country is 'xx' - will log in and enable Meshnet, but not connect."
fi

# The daemon and the network both need to be up. autostart.sh runs from a
# login shell that can win the race against dhcpcd, so wait rather than fail.
rec_log "Waiting for network connectivity..."
for _ in {1..30}; do
    rec_online && break
    sleep 2
done
if ! rec_online; then
    rec_warn "No network after 60s - skipping VPN setup."
    exit 0
fi

# Group membership only applies at login. If this session lacks it, every
# nordvpn call returns "Permission denied" with unhelpful advice.
if ! rec_in_group nordvpn; then
    rec_warn "This session is not in the 'nordvpn' group - skipping."
    rec_warn "Run: sudo usermod -aG nordvpn $USER   then reboot."
    exit 0
fi

# Log in only if we are not already logged in; repeated logins error out.
if ! nordvpn account >/dev/null 2>&1; then
    if [[ -n "${NORDVPN_TOKEN:-}" ]]; then
        rec_log "Logging in to NordVPN with the configured token."
        if nordvpn login --token "$NORDVPN_TOKEN"; then
            ok_login=1
        else
            rec_warn "Token login failed - check NORDVPN_TOKEN in config.sh."
            exit 0
        fi
    else
        rec_warn "Not logged in and NORDVPN_TOKEN is empty."
        rec_warn "Run 'nordvpn login' once by hand, or set the token in config.sh."
        exit 0
    fi
else
    rec_log "Already logged in."
fi

# Keep the LAN reachable while the tunnel is up, otherwise SSH, the Kore
# remote and the port forwards all stop working the moment the VPN connects.
if [[ -n "${NORDVPN_LAN_SUBNET:-}" ]]; then
    nordvpn allowlist add subnet "$NORDVPN_LAN_SUBNET" >/dev/null 2>&1 \
        || nordvpn whitelist add subnet "$NORDVPN_LAN_SUBNET" >/dev/null 2>&1 \
        || rec_warn "Could not add $NORDVPN_LAN_SUBNET to the NordVPN allowlist."
fi

if [[ "${NORDVPN_MESHNET:-on}" == "on" ]]; then
    nordvpn set meshnet on >/dev/null 2>&1 \
        && rec_log "Meshnet enabled." \
        || rec_warn "Could not enable Meshnet."
fi

if (( connect_at_boot == 0 )); then
    rec_log "Setup complete; leaving the tunnel disconnected as configured."
    exit 0
fi

if nordvpn status 2>/dev/null | grep -q "Status: Connected"; then
    rec_log "VPN is already connected."
    exit 0
fi

rec_log "Connecting to ${countries[0]}."
nordvpn connect "${countries[0]}"
