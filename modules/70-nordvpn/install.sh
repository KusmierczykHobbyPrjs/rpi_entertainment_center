#!/bin/bash
# ---------------------------------------------------------------------------
# 70-nordvpn - VPN plus Meshnet.
#
# Two separate things, both from the same client:
#   VPN     - outbound traffic leaves through another country. Used to reach
#             region-locked catch-up TV.
#   Meshnet - a private network between your own devices. This is what makes
#             the Pi (and, through the port forwards, the devices behind it)
#             reachable from anywhere without exposing anything publicly.
#
# See docs/70-nordvpn.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"
rec_load_config

require_not_root

step "Installing the NordVPN client"
if rec_has nordvpn; then
    skip "nordvpn is already installed ($(nordvpn --version 2>/dev/null | head -1))"
else
    note "Downloading and running NordVPN's official installer"
    # NordVPN is not in the Debian archive; this is the vendor's documented
    # install path for Raspberry Pi.
    if curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh -o /tmp/nordvpn-install.sh; then
        sh /tmp/nordvpn-install.sh || { fail "NordVPN installer failed"; exit 1; }
        rm -f /tmp/nordvpn-install.sh
        ok "NordVPN installed"
    else
        fail "Could not download the NordVPN installer. Check your connection."
        exit 1
    fi
fi

step "Adding $USER to the nordvpn group"
# Without this every nordvpn command needs sudo, which the button scripts and
# the Kodi menu cannot supply.
if id -nG "$USER" | grep -qw nordvpn; then
    skip "$USER is already in the 'nordvpn' group"
else
    sudo usermod -aG nordvpn "$USER"
    ok "Added $USER to 'nordvpn' (takes effect after the next login)"
    note "Until you log out and back in, nordvpn commands may fail with a permission error."
fi

step "Starting the NordVPN daemon"
sudo systemctl enable --now nordvpnd 2>/dev/null || skip "Could not enable nordvpnd via systemd"
sleep 2

step "Logging in"
if nordvpn account >/dev/null 2>&1; then
    skip "Already logged in"
elif [[ -n "${NORDVPN_TOKEN:-}" ]]; then
    if nordvpn login --token "$NORDVPN_TOKEN"; then
        ok "Logged in with the token from config.sh"
    else
        fail "Token login failed. Generate a fresh token at:"
        fail "  https://my.nordaccount.com/dashboard/nordvpn/ -> Access token"
        fail "then put it in NORDVPN_TOKEN in config.sh and re-run this module."
    fi
else
    skip "NORDVPN_TOKEN is empty in config.sh"
    cat <<EOF

  Get a token from:
      https://my.nordaccount.com/dashboard/nordvpn/  ->  "Access token"
  Put it in config.sh as NORDVPN_TOKEN="...", then re-run:
      ./install.sh 70-nordvpn

  Or log in interactively right now with:  nordvpn login

EOF
fi

step "Allowing LAN traffic through the tunnel"
# Without this, connecting the VPN cuts off SSH, the Kore remote and every
# port forward, because all LAN traffic gets routed into the tunnel.
if [[ -n "${NORDVPN_LAN_SUBNET:-}" ]]; then
    if nordvpn allowlist add subnet "$NORDVPN_LAN_SUBNET" 2>/dev/null \
       || nordvpn whitelist add subnet "$NORDVPN_LAN_SUBNET" 2>/dev/null; then
        ok "Allowlisted $NORDVPN_LAN_SUBNET"
    else
        skip "Could not set the allowlist (not logged in yet?) - re-run after logging in"
    fi

    # Sanity-check the subnet against the Pi's actual address.
    my_ip="$(hostname -I | awk '{print $1}')"
    if [[ -n "$my_ip" && "${NORDVPN_LAN_SUBNET%.*/*}" != "${my_ip%.*}" ]]; then
        fail "This Pi is at $my_ip but NORDVPN_LAN_SUBNET is $NORDVPN_LAN_SUBNET"
        fail "Those do not match - fix NORDVPN_LAN_SUBNET in config.sh, or SSH"
        fail "will drop the moment the VPN connects."
    fi
else
    skip "NORDVPN_LAN_SUBNET is empty in config.sh"
fi

step "Enabling Meshnet"
if [[ "${NORDVPN_MESHNET:-on}" == "on" ]]; then
    if nordvpn set meshnet on 2>/dev/null; then
        ok "Meshnet enabled"
    else
        skip "Could not enable Meshnet (not logged in yet?)"
    fi
else
    skip "Meshnet disabled in config.sh"
fi

echo
ok "NordVPN configured."
cat <<EOF

${REC_C_BOLD}Country rotation${REC_C_OFF}

  NORDVPN_COUNTRIES in config.sh is currently: ${NORDVPN_COUNTRIES:-<unset>}

  Each press of the VPN button (GPIO 17) or "VPN next country" in the Kodi
  menu moves one step along that list and wraps around. The entry "xx" means
  "disconnected", so leaving it in gives you a no-VPN position.

${REC_C_BOLD}Reaching this Pi from anywhere${REC_C_OFF}

  1. Install NordVPN on your phone or laptop and log into the same account.
  2. Enable Meshnet there too.
  3. The Pi appears in the Meshnet device list with a permanent name and IP.
  4. Use that address for SSH, for Kore, and for the forwarded ports from
     module 75-port-forwarding.

  Check the Pi's Meshnet address with:  nordvpn meshnet peer list
EOF
