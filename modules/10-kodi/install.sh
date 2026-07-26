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

step "Granting the access Kodi needs to run from a console"
# Kodi started from tty1 has no desktop session behind it: it talks to the GPU
# through /dev/dri directly (GBM/KMS), reads input devices itself, and must own
# the terminal. Without these groups it exits immediately with a permissions
# error that says nothing useful.
#
# These were previously only granted by the RetroPie module, so a Kodi-only
# install silently lacked them.
for grp in video render input audio tty; do
    if getent group "$grp" >/dev/null 2>&1; then
        if id -nG "$USER" | grep -qw "$grp"; then
            skip "$USER is already in '$grp'"
        else
            sudo usermod -a -G "$grp" "$USER"
            ok "Added $USER to '$grp'"
            REC_NEED_RELOGIN=1
        fi
    fi
done
[[ "${REC_NEED_RELOGIN:-0}" == "1" ]] && \
    note "Group changes take effect at your next login - reboot before testing."

step "Working out how to start Kodi without a desktop"
# Debian ships several Kodi front-ends. The bare "kodi" command is a wrapper
# that prefers the X11 build, which cannot start from a plain console. Pick
# the one that actually works here and report it, because this is what goes
# into REC_UI_START.
KODI_START=""
KODI_PROCESS=""
if rec_has kodi-standalone; then
    # Wraps Kodi in its own minimal session; the usual choice on Raspberry Pi OS.
    KODI_START="kodi-standalone"
    KODI_PROCESS="kodi-standalone"
    ok "Found kodi-standalone (starts without a desktop session)"
elif rec_has kodi-gbm; then
    KODI_START="kodi-gbm"
    KODI_PROCESS="kodi-gbm"
    ok "Found kodi-gbm (renders directly via KMS, no X needed)"
else
    KODI_START="kodi"
    KODI_PROCESS="kodi"
    fail "Only the plain 'kodi' wrapper is available."
    fail "It prefers the X11 build and will not start from a bare console."
    note "Try: sudo apt install kodi-standalone   (or kodi-gbm)"
fi

# The process that ends up running is often not named like the command that
# started it, and the UI watchdog matches on process name.
note "After starting Kodi, confirm the process name with:  ps -A | grep -i kodi"

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
cat <<EOF

${REC_C_BOLD}Use these values in config.sh${REC_C_OFF}

    REC_UI_PROCESSES=( "${KODI_PROCESS}" ... )
    REC_UI_START=(     "${KODI_START} &" ... )
    REC_UI_STOP=(      "kodi-send --action=\"Quit\"" ... )

The default in config.example.sh is plain "kodi", which is the X11 wrapper and
will NOT start from a console. If Kodi never appears at boot, this is the
first thing to check.

EOF
note "Finish the Kore remote setup inside Kodi:"
note "  Settings > Services > Control > Allow remote control via HTTP"
note "See docs/10-kodi.md for the full walkthrough."
