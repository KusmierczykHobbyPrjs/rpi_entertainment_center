#!/bin/bash
# ---------------------------------------------------------------------------
# 40-desktop - the ordinary Raspbian desktop, as the third UI.
#
# Kodi covers media and RetroPie covers games, but some things need a real
# browser: web-only video players, webmail, a bank. This module makes LXDE
# usable from the sofa by pinning it to a resolution the Pi can actually
# drive.
#
# Note this does NOT switch the Pi to booting into the desktop - the UI
# switcher starts it on demand with `startx`.
#
# See docs/40-desktop.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

step "Installing the LXDE desktop"
apt_install lxde-core lxde-common openbox-lxde-session || exit 1

step "Installing X server utilities"
# xrandr (in x11-xserver-utils) is what desktop_set_resolution.sh uses;
# xinit provides startx, which is how the UI switcher launches the desktop.
apt_install x11-xserver-utils xinit || exit 1

step "Installing Chromium"
apt_install chromium-browser || apt_install chromium || exit 1

step "Pinning the desktop resolution"
# LXDE reads every .desktop-style line in this autostart file when a session
# starts. Using a marker block keeps re-runs from stacking duplicate lines.
LXDE_AUTOSTART="/etc/xdg/lxsession/LXDE-pi/autostart"
if [[ ! -f "$LXDE_AUTOSTART" ]]; then
    # The directory name follows the session name, which differs between
    # Raspberry Pi OS ("LXDE-pi") and plain Debian ("LXDE").
    ALT="/etc/xdg/lxsession/LXDE/autostart"
    [[ -f "$ALT" ]] && LXDE_AUTOSTART="$ALT"
fi

if [[ -f "$LXDE_AUTOSTART" ]]; then
    ensure_block "$LXDE_AUTOSTART" "rpi-entertainment-center" \
"@bash $REC_BIN/desktop_set_resolution.sh"
else
    fail "Could not find the LXDE autostart file."
    fail "Add this line to it by hand once you know where it is:"
    fail "  @bash $REC_BIN/desktop_set_resolution.sh"
fi

step "Checking the configured resolution"
note "config.sh currently asks for: \${REC_DESKTOP_MODE} on \${REC_DESKTOP_OUTPUT}"
note "List what your TV actually supports with:  DISPLAY=:0 xrandr"

echo
ok "Desktop installed."
cat <<EOF

${REC_C_BOLD}How the desktop fits in${REC_C_OFF}

  - It is one position in the UI rotation, not the boot target. Press the
    "switch UI" button (or use the Kodi menu) until you reach it.
  - Start it by hand for testing with:  startx
  - Leave it the same way you leave the others: the switch-UI button.

If the picture is the wrong size or the browser is unusably slow, adjust
REC_DESKTOP_MODE in config.sh - see docs/40-desktop.md.
EOF
