#!/bin/bash
# ---------------------------------------------------------------------------
# 10-kodi - the media centre.
#
# Installs Kodi with the pieces the rest of the project relies on: adaptive
# streaming (needed by almost every modern video add-on), the joystick driver
# (so the RetroPie gamepad also drives Kodi) and kodi-send (the command-line
# remote used by the GPIO buttons).
#
# See docs/10-kodi.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

step "Installing Kodi"
apt_install kodi || exit 1

step "Installing streaming support"
# inputstream.adaptive handles DASH/HLS, which is what YouTube, Netflix,
# iPlayer and most catch-up services use. Without it those add-ons install
# fine and then fail to play anything.
apt_install kodi-inputstream-adaptive kodi-inputstream-rtmp || exit 1

step "Installing controller support"
# Lets a USB gamepad drive Kodi's menus, so one controller covers both Kodi
# and RetroPie.
apt_install kodi-peripheral-joystick || exit 1

step "Installing command-line control (kodi-send)"
# kodi-send is how the GPIO buttons tell Kodi to play/pause and how the UI
# switcher asks Kodi to quit cleanly.
apt_install kodi-eventclients-kodi-send || exit 1

step "Enabling Kodi's remote-control interface"
# Kore (the official Android/iOS remote) talks to Kodi over its JSON-RPC web
# interface, which is off by default. Writing the setting here means the
# remote works on first boot instead of needing a keyboard to enable it.
KODI_USERDATA="$HOME/.kodi/userdata"
mkdir -p "$KODI_USERDATA"

if [[ -f "$KODI_USERDATA/advancedsettings.xml" ]]; then
    skip "advancedsettings.xml already exists - leaving it alone"
    note "Make sure 'Settings > Services > Control' has remote control enabled."
else
    cat > "$KODI_USERDATA/advancedsettings.xml" <<'XML'
<advancedsettings>
  <!--
    Written by the rpi-entertainment-center installer.

    Kodi still needs the switches under
      Settings > Services > Control
    turned on for the Kore remote to connect:
      - Allow remote control via HTTP        (port 8080)
      - Allow remote control from applications on other systems
    The installer cannot set those from outside a running Kodi, so do it once
    from the Kodi UI. See docs/10-kodi.md.
  -->
  <videolibrary>
    <!-- A Pi 3B is slow at scanning; do it in the background. -->
    <backgroundupdate>true</backgroundupdate>
  </videolibrary>
</advancedsettings>
XML
    ok "Created $KODI_USERDATA/advancedsettings.xml"
fi

echo
ok "Kodi installed."
note "Finish the Kore remote setup inside Kodi:"
note "  Settings > Services > Control > Allow remote control via HTTP"
note "See docs/10-kodi.md for the full walkthrough."
