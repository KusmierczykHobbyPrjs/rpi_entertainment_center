#!/bin/bash
# ---------------------------------------------------------------------------
# 95-weather - spoken weather reports.
#
# Reads the current conditions from OpenWeatherMap and speaks them in the
# language configured for the rest of the system. Useful bound to a GPIO
# button or a Kodi menu entry.
#
# Needs a free OpenWeatherMap API key in config.sh.
#
# See docs/95-weather.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"
rec_load_config

require_not_root

step "Checking dependencies"
# weather.py deliberately uses only the Python standard library, so there is
# nothing to install beyond python3 itself.
if rec_has python3; then
    ok "python3 is available (weather.py needs no extra packages)"
else
    fail "python3 is missing - run: ./install.sh 00-base"
    exit 1
fi

if [[ -f "$REC_BIN/speech.sh" ]] && rec_has mpg123; then
    ok "Speech is available"
else
    skip "Speech is not set up yet - run: ./install.sh 90-speech"
    note "weather.py still works on its own and prints to stdout."
fi

step "Checking the API key"
if [[ -n "${OPENWEATHER_API_KEY:-}" ]]; then
    ok "OPENWEATHER_API_KEY is set"
else
    fail "OPENWEATHER_API_KEY is empty in config.sh"
    cat <<EOT

  Get a free key:
    1. Sign up at https://openweathermap.org/api
    2. Copy the key from your account page
    3. Put it in config.sh:  export OPENWEATHER_API_KEY="..."
    4. Re-run:  ./install.sh 95-weather

  A brand new key can take up to a couple of hours to start working.

EOT
    exit 1
fi

step "Checking the location setting"
location="${REC_WEATHER_LOCATION:-auto}"
if [[ "$location" == "auto" ]]; then
    ok "Location: auto (detected from the public IP)"
    note "With the VPN connected this reports the exit country, not where you are."
    note "Set REC_WEATHER_LOCATION to a city or \"lat,lon\" if that matters."
else
    ok "Location: $location"
fi

step "Testing a live report"
if confirm "Fetch the weather now?"; then
    if report="$(python3 "$REC_BIN/weather.py")"; then
        ok "Report: $report"
    else
        fail "Could not fetch the weather - see the message above."
        exit 1
    fi
else
    skip "Skipped. Test later with: python3 $REC_BIN/weather.py"
fi

echo
ok "Weather configured."
cat <<EOT

${REC_C_BOLD}Usage${REC_C_OFF}

    python3 $REC_BIN/weather.py            print the report
    bash $REC_BIN/say_weather.sh           speak it
    bash $REC_BIN/say_weather.sh Helsinki  override the location once

${REC_C_BOLD}Bind it to a button${REC_C_OFF} - add to REC_GPIO_BUTTONS in config.sh:

    "5:bash \$REC_BIN/say_weather.sh"

It is already in the Kodi Shell Script Launcher menu as "Weather".
EOT
