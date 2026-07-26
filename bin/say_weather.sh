#!/bin/bash
# ---------------------------------------------------------------------------
# say_weather.sh - speak the current weather.
#
#   say_weather.sh                 configured location, configured language
#   say_weather.sh Helsinki        override the location for this run
#   say_weather.sh "60.17,24.94"   explicit coordinates
#
# Both the greeting and the forecast use $SPEECH_LANG from config.sh, so this
# replaces the old Polish-only say_weather_pl.sh.
#
# Bind it to a GPIO button or a Kodi menu entry - see docs/95-weather.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

LANG_CODE="${SPEECH_LANG:-en}"

# Greeting in the configured language. Falls through to English for anything
# not listed, which still reads correctly alongside a translated forecast.
case "$LANG_CODE" in
    pl) GREETING="Dzień dobry! Na dworze" ;;
    de) GREETING="Guten Tag! Draußen ist es" ;;
    fi) GREETING="Hyvää päivää! Ulkona on" ;;
    en) GREETING="Good day! Outside it is" ;;
    *)  GREETING="" ;;
esac

# weather.py prints the forecast on stdout and its diagnostics on stderr, so
# only the sentence itself ends up being spoken.
if ! REPORT="$(python3 "$REC_BIN/weather.py" "$@")"; then
    rec_error "Could not get the weather - see the message above."
    exit 1
fi

[[ -n "$REPORT" ]] || { rec_warn "Weather report was empty."; exit 1; }

rec_log "$GREETING $REPORT"
bash "$REC_BIN/speech.sh" "$LANG_CODE" "$GREETING $REPORT"
