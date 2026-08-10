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
# B2 = console with autologin. The project needs a plain console session,
# because autostart.sh (run from .bashrc) is what decides which UI starts.
# Booting to the desktop takes that decision away - and is what happens by
# default on a Raspberry Pi OS "with desktop" image.
if rec_has raspi-config; then
    sudo raspi-config nonint do_boot_behaviour B2 >/dev/null 2>&1
    sudo raspi-config nonint do_boot_wait 0 >/dev/null 2>&1
fi

# Do not trust the exit code - verify. On some releases raspi-config returns
# success without changing anything, and the failure only shows up as "the Pi
# booted to the desktop and nothing started".
boot_ok=1
target="$(systemctl get-default 2>/dev/null)"
if [[ "$target" == "multi-user.target" ]]; then
    ok "Boot target is multi-user.target (console)"
else
    fail "Boot target is '$target', not multi-user.target"
    boot_ok=0
fi

if [[ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]]; then
    ok "Console autologin is configured"
else
    fail "Console autologin is NOT configured"
    boot_ok=0
fi

# A display manager left enabled will grab the screen even with the right
# boot target, which looks identical to "autostart did not run".
for dm in lightdm gdm3 sddm greetd; do
    if systemctl is-enabled --quiet "$dm" 2>/dev/null; then
        fail "Display manager '$dm' is still enabled and will take over the screen"
        note "Disable it with: sudo systemctl disable $dm"
        boot_ok=0
    fi
done

if [[ $boot_ok -eq 0 ]]; then
    cat <<EOF

  ${REC_C_BOLD}Boot behaviour could not be set automatically.${REC_C_OFF}

  Without this the Pi boots into the desktop, ~/.bashrc never runs on the
  console, and none of the background services start - which looks like
  everything is broken.

  Fix it by hand, then re-run this module:

      sudo raspi-config
        -> System Options -> Boot / Auto Login -> Console Autologin

  Verify with:

      systemctl get-default          # want: multi-user.target

EOF
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

# --- Autostart hook --------------------------------------------------------
step "Hooking autostart.sh into the login shell"
# A marker block rather than a bare appended line, so re-running the installer
# (or moving the repository) updates the path instead of adding a second copy.
ensure_block "$HOME/.bashrc" "rpi-entertainment-center" \
"# Starts the UI watchdog, VPN, GPIO buttons and port forwarding.
# autostart.sh exits immediately unless it is running on the physical
# console (/dev/tty1), so SSH logins are unaffected.
#
# Deliberately NOT backgrounded with '&'. It looks like an omission; it is not.
# Backgrounding it leaves THIS shell sitting at its prompt reading /dev/tty1
# while the UI stack reads the same terminal. Both then receive part of every
# keystroke - arrow keys arrive as broken escape sequences - and both fight
# over the echo setting. RetroPie's launch menu is unusable as a result.
# Backgrounding also makes bash point the whole chain's stdin at /dev/null.
[ -f \"$REC_BIN/autostart.sh\" ] && bash \"$REC_BIN/autostart.sh\""

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
