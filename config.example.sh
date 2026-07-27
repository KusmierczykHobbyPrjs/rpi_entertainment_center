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
#
# The desktop entry assumes Wayland (the default from Bookworm on). Under X11
# the process is "Xorg" instead - see REC_UI_START below.
REC_UI_PROCESSES=("kodi" "emulationstatio" "labwc")

# Human-readable names, used in log lines and spoken messages.
REC_UI_NAMES=("Kodi" "RetroPie" "Desktop")

# Command that starts each UI.
#
# IMPORTANT - both of these are easy to get wrong, and both give a black
# screen at boot with no explanation:
#
#   Kodi: the bare "kodi" command is a wrapper that prefers the X11 build and
#         CANNOT start from a console with no desktop. Use "kodi-standalone"
#         (or "kodi-gbm"). Module 10-kodi detects which you have.
#
#   Desktop: you must start the SESSION, not the compositor. Running "labwc"
#         or "startx" on their own gives a bare compositor - no panel, no file
#         manager, no autostart. On Raspberry Pi OS the session commands are:
#
#             labwc-pi      Wayland  (the default from Bookworm on)
#             startx-rpd    X11
#
#         Module 40-desktop reads these from the session .desktop files and
#         tells you which applies. Check which display server you have with:
#             raspi-config nonint get_wayland     # 0 = Wayland, 1 = X11
#
# Defaults below assume Wayland. For X11 use:
#     REC_UI_PROCESSES=(... "Xorg")
#     REC_UI_START=(...     "startx-rpd &")
#     REC_UI_STOP=(...      "killall Xorg")
REC_UI_START=("kodi-standalone &" "emulationstation &" "labwc-pi &")

# Command that cleanly stops each UI.
# The desktop entry kills the wrapper and the compositor - labwc-pi may exec
# labwc and disappear, so the second command is the one that usually does it.
REC_UI_STOP=("kodi-send --action=\"Quit\"" "pkill emulationstatio" "pkill -x labwc-pi; pkill -x labwc")

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
# Format: "BCM_PIN:command"  or  "BCM_PIN@HOLD_MS:command"
#
# HOLD_MS is how long the pin must stay low before the press is believed.
# Default 50 ms. This rejects electrical crosstalk between adjacent header
# pins - without it, pressing one button can fire its neighbour, and with
# shutdown on GPIO 3 that is memorable.
#
# Give destructive actions a longer hold: 1500 ms means shutdown needs a
# deliberate press-and-hold rather than a brush.
#
# See docs/HARDWARE.md for the wiring diagram and the pin numbering scheme.
#
# $REC_BIN is expanded at runtime and points at this repository's bin/ folder.
REC_GPIO_BUTTONS=(
    "3@1500:sudo shutdown now"
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
# LEAVE EMPTY to keep whatever the display negotiates. That is the right
# setting unless you have a specific reason: a mode your TV does not advertise
# is simply rejected, and the desktop then starts at whatever it would have
# used anyway.
#
# Only set these if the desktop is too slow at your TV's native resolution -
# a Pi 3B cannot play video in a browser at 1080p. Pick a mode from the list
# your own display reports (see above); do not copy one from a guide.
#
#   export REC_DESKTOP_MODE="1280x720"
export REC_DESKTOP_OUTPUT=""
export REC_DESKTOP_MODE=""
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
