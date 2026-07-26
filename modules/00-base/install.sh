#!/bin/bash
# ---------------------------------------------------------------------------
# 00-base - the foundation every other module builds on.
#
# Installs the shared packages, creates config.sh, makes the scripts
# executable, switches the Pi to console autologin and hooks autostart.sh into
# the login shell.
#
# See docs/00-base.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

# --- Packages --------------------------------------------------------------
step "Installing base packages"
apt_install \
    git curl wget unzip \
    python3 python3-pip \
    util-linux \
    ca-certificates || exit 1

step "Installing filesystem support for USB drives"
# Raspberry Pi OS cannot read NTFS (most external drives) or exFAT (most large
# USB sticks) out of the box, which is the usual reason a drive full of media
# "does not show up".
apt_install ntfs-3g exfat-fuse || exit 1
# The exFAT tools package was renamed between Raspberry Pi OS releases.
apt_install exfatprogs 2>/dev/null || apt_install exfat-utils 2>/dev/null || \
    skip "No exFAT tools package available under either name"

# --- Configuration file ----------------------------------------------------
step "Creating the configuration file"
ensure_config

# --- Permissions -----------------------------------------------------------
step "Making the scripts executable"
chmod +x "$REC_BIN"/*.sh "$REC_BIN"/*.py 2>/dev/null
chmod +x "$REC_ROOT/install.sh"
chmod +x "$REC_MODULES"/*/install.sh
ok "Set the executable bit on bin/ and the module installers"

# --- Boot behaviour --------------------------------------------------------
step "Configuring boot behaviour"
if rec_has raspi-config; then
    # B2 = console with autologin. The project needs a plain console session,
    # because autostart.sh (run from .bashrc) is what decides which UI starts.
    # Booting straight to the desktop would take that decision away.
    if sudo raspi-config nonint do_boot_behaviour B2; then
        ok "Boot set to 'Console Autologin'"
    else
        fail "Could not set boot behaviour - do it manually:"
        fail "  sudo raspi-config -> System Options -> Boot / Auto Login -> Console Autologin"
    fi

    # Wait for the network before handing control to the login shell, so that
    # the VPN autostart is not racing dhcpcd on every boot.
    if sudo raspi-config nonint do_boot_wait 0; then
        ok "Boot now waits for the network"
    else
        skip "Could not enable 'wait for network' - set it in raspi-config if VPN autostart is flaky"
    fi
else
    skip "raspi-config not found - set 'Console Autologin' by hand"
fi

# --- Autostart hook --------------------------------------------------------
step "Hooking autostart.sh into the login shell"
# A marker block rather than a bare appended line, so re-running the installer
# (or moving the repository) updates the path instead of adding a second copy.
ensure_block "$HOME/.bashrc" "rpi-entertainment-center" \
"# Starts the UI watchdog, VPN, GPIO buttons and port forwarding.
# autostart.sh exits immediately unless it is running on the physical
# console (/dev/tty1), so SSH logins are unaffected.
[ -f \"$REC_BIN/autostart.sh\" ] && bash \"$REC_BIN/autostart.sh\" &"

# --- Remove the old-style hook ---------------------------------------------
# Earlier versions of this project appended a bare 'bash autostart.sh &' line
# that only worked when the scripts lived directly in the home directory.
if grep -qE '^\s*bash\s+autostart\.sh\s*&\s*$' "$HOME/.bashrc" 2>/dev/null; then
    step "Removing the legacy autostart line from .bashrc"
    backup_file "$HOME/.bashrc"
    sed -i -E '/^\s*bash\s+autostart\.sh\s*&\s*$/d' "$HOME/.bashrc"
    ok "Legacy line removed (see .bashrc.rec-backup)"
fi

echo
ok "Base setup complete."
note "Review your settings now: nano $REC_ROOT/config.sh"
