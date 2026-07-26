#!/bin/bash
# ---------------------------------------------------------------------------
# 30-retropie - retro gaming.
#
# RetroPie has no Debian package; it is installed by its own setup script,
# which compiles emulators. This module clones RetroPie-Setup and hands over
# to its menu, because emulator choice is personal and the menu is the
# supported way to make it.
#
# Expect this to take a long time on a Pi 3B - an hour or more if you install
# the full "basic install" set.
#
# See docs/30-retropie.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

RETROPIE_SETUP="$HOME/RetroPie-Setup"

step "Installing RetroPie build dependencies"
apt_install git dialog unzip xmlstarlet || exit 1

step "Fetching RetroPie-Setup"
if [[ -d "$RETROPIE_SETUP/.git" ]]; then
    skip "RetroPie-Setup already present - updating"
    git -C "$RETROPIE_SETUP" pull --ff-only || \
        skip "Could not update (local changes?) - continuing with what is there"
else
    git clone --depth 1 https://github.com/RetroPie/RetroPie-Setup.git "$RETROPIE_SETUP" || exit 1
    ok "Cloned RetroPie-Setup"
fi
chmod +x "$RETROPIE_SETUP/retropie_setup.sh"

step "Granting the console access it needs"
# EmulationStation starts X-less on tty1 and needs the calling user to own the
# terminal. Without this, `emulationstation` exits immediately with a
# permissions error that gives no hint about the cause.
if id -nG "$USER" | grep -qw tty; then
    skip "$USER is already in the 'tty' group"
else
    sudo usermod -a -G tty "$USER"
    ok "Added $USER to the 'tty' group (takes effect after the next login)"
fi

# input/video/audio groups are what let a plain user reach the gamepad, the
# framebuffer and the sound card from the console.
for grp in input video audio; do
    if id -nG "$USER" | grep -qw "$grp"; then
        skip "$USER is already in the '$grp' group"
    else
        sudo usermod -a -G "$grp" "$USER"
        ok "Added $USER to the '$grp' group"
    fi
done

echo
cat <<EOF
${REC_C_BOLD}RetroPie's own installer will now open.${REC_C_OFF}

In its menu choose:
    "Basic install"   - the core packages plus the common emulators
                        (recommended; takes 45-90 minutes on a Pi 3B)
  or
    "Manage packages" - pick individual emulators if you know what you want

EOF
if confirm "Open the RetroPie setup menu now?"; then
    sudo "$RETROPIE_SETUP/retropie_setup.sh"
else
    skip "Skipped. Run it later with:"
    note "  sudo $RETROPIE_SETUP/retropie_setup.sh"
fi

echo
ok "RetroPie module finished."
cat <<EOF

${REC_C_BOLD}Next steps${REC_C_OFF}

  1. Copy ROMs to ~/RetroPie/roms/<system>/ (for example ~/RetroPie/roms/snes/).
     Over the network they also appear at \\\\$(hostname)\\roms if Samba is installed.

  2. Start EmulationStation once to configure your controller:
         emulationstation
     It walks you through the button mapping on first run.

  3. If a USB gamepad is not detected, see the joystick section in
     docs/30-retropie.md - some generic pads need their vendor/product IDs
     added to the RetroArch autoconfig file by hand.

  4. Log out and back in so the new group memberships take effect.
EOF
