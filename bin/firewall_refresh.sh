#!/bin/bash
# ---------------------------------------------------------------------------
# firewall_refresh.sh - re-open the ports this project's modules need.
#
# THE PROBLEM
#   ufw is turned on by exactly one module, 80-webserver, which is normally
#   the last one installed. Its policy is "deny incoming", and the only ports
#   it opens are SSH, HTTP and HTTPS. Everything else installed before it -
#   Kodi's remote control, Tvheadend, KDE Connect, Samba, Meshnet - is cut off
#   the instant the policy takes effect.
#
#   Nothing reports an error. Kore just stops connecting, kodi-send stops
#   doing anything, and the Pi disappears from Meshnet. It reads exactly like
#   "the Pi broke", which is the worst kind of bug to leave in an installer.
#
# WHAT THIS DOES
#   Looks at what is actually installed on this machine and re-opens each
#   service to the LOCAL NETWORK only - never to the internet. The web server
#   stays public; nothing else becomes public.
#
#   80-webserver runs this automatically. Run it yourself after installing any
#   further module, or any time you are not sure what is open.
#
# USAGE
#   bash bin/firewall_refresh.sh            # re-open ports (ufw must be on)
#   bash bin/firewall_refresh.sh --enable   # install and enable ufw, then open
#   bash bin/firewall_refresh.sh --status   # show the current rules and exit
#
# See docs/80-webserver.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../lib/install_helpers.sh"

require_not_root

case "${1:-}" in
    --status)
        if ! rec_has ufw; then
            skip "ufw is not installed - nothing is being filtered"
            exit 0
        fi
        sudo ufw status verbose
        exit 0
        ;;
    --enable)
        step "Enabling ufw"
        apt_install ufw || exit 1
        # SSH first, always. Enabling a deny-incoming policy over SSH without
        # this rule in place cuts the session that is running this script, and
        # recovery needs a keyboard and monitor attached to the Pi.
        sudo ufw allow OpenSSH >/dev/null 2>&1 || sudo ufw allow 22/tcp >/dev/null
        ok "Allowed SSH (22/tcp) - before enabling, so this session survives"
        if rec_has apache2 || systemctl is-active --quiet apache2 2>/dev/null; then
            sudo ufw allow 80/tcp  >/dev/null
            sudo ufw allow 443/tcp >/dev/null
            ok "Allowed HTTP and HTTPS (a web server is installed)"
        fi
        sudo ufw --force enable
        ok "ufw is active"
        ;;
    "")
        ;;
    *)
        fail "Unknown option: $1"
        note "Usage: bash bin/firewall_refresh.sh [--enable|--status]"
        exit 1
        ;;
esac

step "Re-opening ports for the modules installed on this machine"

if ! ufw_active; then
    skip "ufw is not active - nothing is being blocked, so nothing to open"
    note "Turn it on with: bash bin/firewall_refresh.sh --enable"
    exit 0
fi

lan="$(rec_lan_cidrs | paste -sd' ' -)"
note "Local network detected as: ${lan:-none found}"

rec_ufw_open_project_services

echo
ok "Firewall refreshed."
note "Full rule list: sudo ufw status verbose"
