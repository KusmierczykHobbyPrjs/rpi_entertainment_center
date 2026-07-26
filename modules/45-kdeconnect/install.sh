#!/bin/bash
# ---------------------------------------------------------------------------
# 45-kdeconnect - drive the desktop from a phone.
#
# KDE Connect pairs the Pi with a phone over the LAN and gives you a
# touchpad, a keyboard, clipboard sync and custom commands. Combined with
# clipboard2chromium.sh that means you can copy a link on your phone and have
# it open full-screen on the TV.
#
# Kore covers Kodi and a gamepad covers RetroPie; this is the missing remote
# for the desktop.
#
# See docs/45-kdeconnect.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

step "Installing KDE Connect"
apt_install kdeconnect || exit 1

step "Installing the clipboard tool"
# xclip is how clipboard2chromium.sh reads what the phone sent.
apt_install xclip || exit 1

step "Installing the tray applet (optional)"
apt_install indicator-kdeconnect 2>/dev/null || \
    skip "indicator-kdeconnect is not packaged on this release - pairing still works"

step "Opening the firewall for KDE Connect"
# KDE Connect discovers and talks to peers on TCP+UDP 1714-1764. On a Pi with
# ufw enabled, pairing silently never completes without these rules.
if rec_has ufw && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo ufw allow 1714:1764/udp comment "KDE Connect" >/dev/null
    sudo ufw allow 1714:1764/tcp comment "KDE Connect" >/dev/null
    ok "Allowed TCP/UDP 1714-1764 through ufw"
else
    skip "ufw is not active - no firewall rules needed"
fi

step "Registering the 'Open clipboard URL' command"
# KDE Connect reads its custom commands from this config file. Writing the
# entry here saves a fiddly bit of setup that otherwise has to be done in a
# GUI on the Pi itself.
KDECONF="$HOME/.config/kdeconnect"
if [[ -d "$KDECONF" ]]; then
    note "KDE Connect config found at $KDECONF"
    note "Add the command through the phone app once paired:"
else
    note "Pair a device first, then add the command through the phone app:"
fi
cat <<EOF

    KDE Connect app > (your Pi) > Run command > Add command
      Name:    Open clipboard URL
      Command: bash $REC_BIN/clipboard2chromium.sh

EOF

echo
ok "KDE Connect installed."
cat <<EOF

${REC_C_BOLD}Pairing${REC_C_OFF}

  1. Make sure the phone and the Pi are on the same network.
  2. Switch the Pi to the Desktop UI (KDE Connect needs a running session).
  3. Open the KDE Connect app on the phone; the Pi appears in the list.
  4. Tap it, request pairing, and accept the request on the Pi.

${REC_C_BOLD}Watching a web-only video on the TV${REC_C_OFF}

  1. Copy the URL on your phone.
  2. KDE Connect > Send clipboard.
  3. KDE Connect > Run command > "Open clipboard URL".

See docs/45-kdeconnect.md if the Pi does not appear in the app.
EOF
