#!/bin/bash
# ---------------------------------------------------------------------------
# config.example.sh - template for config.sh
#
# Copy this file to config.sh and edit it:
#
#     cp config.example.sh config.sh
#     nano config.sh
#
# config.sh is listed in .gitignore because it holds secrets. Never commit it.
# Every setting below has a working default, so the only values you MUST
# review are in the "Secrets" section at the bottom.
# ---------------------------------------------------------------------------


# ===========================================================================
# User interfaces
# ===========================================================================
# The project rotates between several full-screen UIs. Exactly one runs at a
# time; pressing the "next UI" button stops the current one and starts the
# next in this list.
#
# The four arrays below are parallel - index 0 of each describes the same UI,
# so they must always have the same number of entries. Remove the entries for
# anything you did not install: if you only want Kodi, cut all four arrays
# down to a single element.
#
# Note there is no `declare -a` here on purpose. These are read by a function,
# and `declare` inside a function would make them local - the scripts would
# then see empty arrays and no UI would ever start.

# Process names as they appear in `ps -A` (used to detect what is running).
# NOTE: Linux truncates process names at 15 characters, which is why
# EmulationStation appears as "emulationstatio" - this is not a typo.
REC_UI_PROCESSES=("kodi" "emulationstatio" "Xorg")

# Human-readable names, used in log lines and spoken messages.
REC_UI_NAMES=("Kodi" "RetroPie" "Desktop")

# Command that starts each UI.
REC_UI_START=("kodi &" "emulationstation &" "startx &")

# Command that cleanly stops each UI.
REC_UI_STOP=("kodi-send --action=\"Quit\"" "pkill emulationstatio" "killall Xorg")

# Which UI starts on boot, given as an index into the arrays above (0 = Kodi).
REC_UI_DEFAULT_INDEX=0


# ===========================================================================
# Audio feedback
# ===========================================================================
# Playback volume for spoken messages and the action beep, as a percentage.
# This is independent of the system mixer volume.
export VOLUME=30

# Short sound played to confirm that a button press or remote command was
# received. Relative paths are resolved against assets/sounds/.
# Set to "" to disable action sounds entirely.
export ACTION_SOUND="signal_action.mp3"

# Language used for spoken status messages (ISO 639-1: en, pl, fi, de, ...).
export SPEECH_LANG="en"


# ===========================================================================
# NordVPN
# ===========================================================================
# Space-separated list of country codes to cycle through when the VPN button
# is pressed. The special code "xx" means "disconnected", so including it
# gives you a no-VPN position in the rotation.
#
# Codes may also carry a server number, e.g. "uk2431" pins a specific server.
export NORDVPN_COUNTRIES="xx pl fi uk"

# Your LAN subnet. It is added to the NordVPN allowlist so that SSH, Kore and
# port forwarding keep working while the VPN tunnel is up. Get yours with:
#     ip route | grep "$(ip route show default | awk '{print $5}')" | grep -o '[0-9.]*/[0-9]*'
export NORDVPN_LAN_SUBNET="192.168.1.0/24"

# Enable NordVPN Meshnet (needed to reach this Pi from outside the LAN).
export NORDVPN_MESHNET="on"


# ===========================================================================
# Port forwarding
# ===========================================================================
# Forward TCP ports on this Pi to other devices on the LAN, so that they
# become reachable through Meshnet / the Pi's public hostname.
#
# Format: one "LISTEN_PORT:TARGET_HOST:TARGET_PORT" entry per array element.
# The example forwards Pi port 8282 to an IP webcam at 192.168.1.20:8080.
REC_PORT_FORWARDS=(
    "8282:192.168.1.20:8080"
)


# ===========================================================================
# GPIO buttons
# ===========================================================================
# Physical buttons wired between a GPIO pin and GND. Each entry maps a BCM
# pin number to the command run when the button is pressed.
#
# Format: "BCM_PIN:command with arguments"
# See docs/HARDWARE.md for the wiring diagram and the pin numbering scheme.
#
# $REC_BIN is expanded at runtime and points at this repository's bin/ folder.
REC_GPIO_BUTTONS=(
    "3:sudo shutdown now"
    "4:bash $REC_BIN/stop_current_ui.sh"
    "17:bash $REC_BIN/nordvpn_rotate.sh"
    "22:kodi-send -a PlayerControl(Play)"
    "27:kodi-send -a PlayPvrRadio"
)


# ===========================================================================
# Desktop
# ===========================================================================
# Fixed resolution for the LXDE desktop session. The desktop otherwise uses
# the maximum mode the TV reports, which is often too slow for a Pi 3B when
# playing video in a browser.
#
# Find your output name and available modes with: xrandr
export REC_DESKTOP_OUTPUT="HDMI-1"
export REC_DESKTOP_MODE="1360x768"
export REC_DESKTOP_RATE="60"


# ===========================================================================
# Secrets  -  REVIEW THESE
# ===========================================================================
# NordVPN access token. Generate one at:
#     https://my.nordaccount.com/dashboard/nordvpn/  ->  "Access token"
# Leave empty to skip automatic VPN login (you can still run `nordvpn login`
# by hand).
export NORDVPN_TOKEN=""
