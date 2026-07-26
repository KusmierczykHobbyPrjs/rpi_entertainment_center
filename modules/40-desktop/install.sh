#!/bin/bash
# ---------------------------------------------------------------------------
# 40-desktop - the ordinary desktop, as the third UI.
#
# Kodi covers media and RetroPie covers games, but some things need a real
# browser. This module makes the desktop usable from the sofa.
#
# IMPORTANT: on Bookworm and later, Raspberry Pi OS already ships a desktop
# (the "rpd-*" packages). This module does NOT install another one - doing so
# makes apt remove the shipped desktop, which is how an earlier version of
# this script broke working systems. It only installs what is missing and
# tells you the right settings for config.sh.
#
# See docs/40-desktop.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

# --- What is already here? -------------------------------------------------
step "Looking for an existing desktop"

os_id="$(grep -oP '^VERSION_ID="\K[0-9]+' /etc/os-release 2>/dev/null || echo 0)"
os_name="$(grep -oP '^VERSION_CODENAME=\K.*' /etc/os-release 2>/dev/null || echo unknown)"
note "Detected Debian $os_id ($os_name)"

have_desktop=0
desktop_kind=""

# Raspberry Pi OS ships its desktop as rpd-* metapackages from Bookworm on.
for pkg in rpd-wayland-core rpd-x-core rpd-common; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        have_desktop=1
        desktop_kind="Raspberry Pi Desktop ($pkg)"
        break
    fi
done

# Otherwise look for any session at all.
if [[ $have_desktop -eq 0 ]]; then
    for pkg in lxde-core xfce4 gnome-session kde-plasma-desktop; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            have_desktop=1
            desktop_kind="$pkg"
            break
        fi
    done
fi

if [[ $have_desktop -eq 1 ]]; then
    ok "Found: $desktop_kind"
    skip "Not installing another desktop - that would remove this one"
else
    fail "No desktop environment found (this looks like a Lite image)."
    cat <<EOF

  This module deliberately does not install a desktop on its own, because on
  Raspberry Pi OS the right one depends on your release, and installing the
  wrong metapackage removes the shipped desktop.

  Install one first with the Raspberry Pi's own tooling:

      sudo apt install raspberrypi-ui-mods       # Raspberry Pi Desktop

  then re-run:  ./install.sh 40-desktop

EOF
    exit 1
fi

# --- Which display server? -------------------------------------------------
step "Detecting the display server"

# Bookworm and later default to Wayland (labwc or wayfire). Trixie uses labwc.
# Wayland matters here because xrandr does not work under it at all, and the
# UI switcher needs a different process name and start command.
session_type="x11"
compositor=""

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    session_type="wayland"
elif rec_has labwc && (( os_id >= 12 )); then
    session_type="wayland"
elif rec_has wayfire && (( os_id >= 12 )); then
    session_type="wayland"
fi

if [[ "$session_type" == "wayland" ]]; then
    for c in labwc wayfire; do
        rec_has "$c" && { compositor="$c"; break; }
    done
    ok "Wayland session (compositor: ${compositor:-unknown})"
else
    ok "X11 session"
fi

# --- Tools -----------------------------------------------------------------
step "Installing the tools this module needs"

if [[ "$session_type" == "wayland" ]]; then
    # xrandr is useless under Wayland; wlr-randr is the equivalent for
    # wlroots-based compositors, which is what labwc and wayfire are.
    apt_install wlr-randr || \
        skip "wlr-randr unavailable - set the resolution from Screen Configuration instead"
else
    apt_install x11-xserver-utils xinit || exit 1
fi

step "Installing Chromium"
if dpkg-query -W -f='${Status}' chromium 2>/dev/null | grep -q "ok installed" \
   || dpkg-query -W -f='${Status}' chromium-browser 2>/dev/null | grep -q "ok installed"; then
    skip "Chromium is already installed"
else
    apt_install chromium || apt_install chromium-browser || \
        fail "Could not install Chromium - install it by hand"
fi

# --- Resolution ------------------------------------------------------------
step "Setting up the fixed desktop resolution"

if [[ "$session_type" == "wayland" ]]; then
    # Wayland compositors read autostart from their own config, not from
    # LXDE's. labwc runs ~/.config/labwc/autostart.
    case "$compositor" in
        labwc)
            AUTOSTART="$HOME/.config/labwc/autostart"
            mkdir -p "$(dirname "$AUTOSTART")"
            ensure_line "$AUTOSTART" "bash $REC_BIN/desktop_set_resolution.sh &"
            ;;
        wayfire)
            note "Add this to the [autostart] section of ~/.config/wayfire.ini:"
            note "  rec_resolution = bash $REC_BIN/desktop_set_resolution.sh"
            ;;
        *)
            skip "Unknown compositor - set the resolution from Screen Configuration"
            ;;
    esac
else
    LXDE_AUTOSTART="/etc/xdg/lxsession/LXDE-pi/autostart"
    [[ -f "$LXDE_AUTOSTART" ]] || LXDE_AUTOSTART="/etc/xdg/lxsession/LXDE/autostart"
    if [[ -f "$LXDE_AUTOSTART" ]]; then
        ensure_block "$LXDE_AUTOSTART" "rpi-entertainment-center" \
            "@bash $REC_BIN/desktop_set_resolution.sh"
    else
        skip "No LXDE autostart file found - set the resolution by hand"
    fi
fi

# --- Tell the user what to put in config.sh --------------------------------
step "Settings for config.sh"

if [[ "$session_type" == "wayland" ]]; then
    ui_process="$compositor"
    ui_start="$compositor &"
    ui_stop="pkill -x $compositor"
else
    ui_process="Xorg"
    ui_start="startx &"
    ui_stop="killall Xorg"
fi

echo
ok "Desktop module finished."
cat <<EOF

${REC_C_BOLD}Add the desktop to the UI rotation${REC_C_OFF}

Your session is ${session_type}${compositor:+ (${compositor})}, so the desktop entry in
config.sh must be:

    REC_UI_PROCESSES=( ... "${ui_process}" )
    REC_UI_NAMES=(     ... "Desktop" )
    REC_UI_START=(     ... "${ui_start}" )
    REC_UI_STOP=(      ... "${ui_stop}" )

The defaults in config.example.sh assume X11 ("Xorg" / "startx"). If you are
on Wayland and leave those, the watchdog will try to start an X server that
is not there and you will get a black screen.

Check with:  $REC_BIN/doctor.sh ui

${REC_C_BOLD}Resolution${REC_C_OFF}

    REC_DESKTOP_OUTPUT="${REC_DESKTOP_OUTPUT:-HDMI-1}"
    REC_DESKTOP_MODE="${REC_DESKTOP_MODE:-1360x768}"

List what your TV supports:

EOF
if [[ "$session_type" == "wayland" ]]; then
    echo "    wlr-randr                 # from inside a desktop session"
else
    echo "    DISPLAY=:0 xrandr         # from inside a desktop session"
fi
cat <<EOF

Both only work from within a running desktop session - over SSH with no
session they report "Can't open display" or "compositor not running".

EOF
