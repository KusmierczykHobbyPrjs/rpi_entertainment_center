#!/bin/bash
# ---------------------------------------------------------------------------
# 25-tvheadend - TV backend for real tuner hardware.
#
# Tvheadend handles DVB-T/S/C tuners and network tuners, and adds recording
# and a proper electronic programme guide - none of which the IPTV Simple
# Client does. Only install this if you have tuner hardware; for
# internet-streamed channels, module 15-kodi-iptv is enough.
#
# See docs/25-tvheadend.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

cat <<EOF
Tvheadend is only useful with a TV tuner (a USB DVB stick, or a network
tuner such as an HDHomeRun). If you only stream over the internet, skip this
module and use 15-kodi-iptv instead.

EOF
if ! confirm "Install Tvheadend?"; then
    skip "Skipped Tvheadend."
    exit 0
fi

step "Installing Tvheadend and its Kodi client"
# The apt install runs a debconf dialog asking for an administrator username
# and password. It cannot be skipped, and those are the credentials you will
# use for the web interface on port 9981.
note "You will be asked to create an admin username and password - remember them."
apt_install tvheadend kodi-pvr-tvheadend-hts || exit 1

step "Enabling the Tvheadend service"
sudo systemctl enable --now tvheadend || fail "Could not enable tvheadend.service"

if systemctl is-active --quiet tvheadend; then
    ok "Tvheadend is running"
else
    fail "Tvheadend is not running. Check: sudo journalctl -u tvheadend -n 50"
fi

IP="$(hostname -I | awk '{print $1}')"
echo
ok "Tvheadend installed."
cat <<EOF

${REC_C_BOLD}Next steps${REC_C_OFF}

  1. Open the web interface from any machine on your LAN:
         http://${IP:-<pi-ip>}:9981
     Log in with the username and password you just created.

  2. Configuration > DVB Inputs > TV adapters
     Your tuner should be listed. Enable it, pick your network/region and
     run "Scan" to find channels.

  3. Configuration > Channel/EPG > Channels
     Map the discovered services to channels.

  4. In Kodi, enable the "Tvheadend HTSP Client" add-on and point it at
     127.0.0.1 with the same credentials.

If no adapter is listed, the tuner needs a firmware package - see
docs/25-tvheadend.md.
EOF
