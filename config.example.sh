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
# Under Wayland the desktop is "labwc" or "wayfire", not "Xorg".
REC_UI_PROCESSES=("kodi" "emulationstatio" "Xorg")

# Human-readable names, used in log lines and spoken messages.
REC_UI_NAMES=("Kodi" "RetroPie" "Desktop")

# Command that starts each UI.
#
# IMPORTANT - two of these defaults are wrong on many systems:
#
#   Kodi: the bare "kodi" command is a wrapper that prefers the X11 build and
#         CANNOT start from a console with no desktop. Use "kodi-standalone"
#         (or "kodi-gbm"). Module 10-kodi detects which you have and prints
#         the right one.
#
#   Desktop: "startx" only exists under X11. Bookworm and later default to
#         Wayland, where the command is "labwc" (or "wayfire"). Module
#         40-desktop prints the right one for your session.
#
# Getting these wrong gives a black screen at boot with no explanation.
REC_UI_START=("kodi-standalone &" "emulationstation &" "startx &")

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
# Weather
# ===========================================================================
# Where to report the weather for. Three accepted forms:
#
#   "auto"              detect the location from this machine's public IP
#   "Helsinki"          a city name (add a country to disambiguate:
#                       "Cambridge,GB" - there are several Cambridges)
#   "60.17,24.94"       explicit latitude,longitude - always unambiguous
#
# WARNING about "auto": IP geolocation reports where your traffic leaves the
# internet, which is the VPN exit node whenever the tunnel is up. Since this
# system rotates the VPN between countries, "auto" will cheerfully announce
# the weather in Finland or the UK depending on what the VPN is doing. If you
# use the VPN, set a fixed city or coordinates instead.
export REC_WEATHER_LOCATION="auto"

# "metric" for Celsius, "imperial" for Fahrenheit.
export REC_WEATHER_UNITS="metric"

# The spoken language comes from SPEECH_LANG above - the forecast wording and
# the greeting both follow it, so there is nothing extra to set here.


# ===========================================================================
# Desktop
# ===========================================================================
# Fixed resolution for the desktop session. The desktop otherwise uses the
# maximum mode the TV reports, which is often too slow for a Pi 3B when
# playing video in a browser.
#
# Find your output name and available modes FROM INSIDE a desktop session:
#     wlr-randr             Wayland (Bookworm and later - the default)
#     DISPLAY=:0 xrandr     X11
# Over SSH with no session both fail; xrandr also fails under Wayland
# entirely, which is what "Can't open display" usually means.
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

# OpenWeatherMap API key, used by the weather scripts. Get a free one at:
#     https://openweathermap.org/api
# A newly created key can take up to a couple of hours to start working.
# Leave empty if you do not want the weather module.
export OPENWEATHER_API_KEY=""
