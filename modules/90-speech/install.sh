#!/bin/bash
# ---------------------------------------------------------------------------
# 90-speech - spoken status messages.
#
# The Pi is normally driven with no screen showing a shell, so events like
# "the VPN dropped" have to be announced out loud to be noticed at all. The
# same mechanism plays the short beep that confirms a button press.
#
# Speech uses Google Translate's public text-to-speech endpoint: no API key,
# no account, and no local voice data - which matters, because the offline
# engines that sound acceptable are too slow on a Pi 3B.
#
# See docs/90-speech.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"
rec_load_config

require_not_root

step "Installing the audio player"
apt_install mpg123 || exit 1

step "Installing audio utilities"
apt_install alsa-utils || exit 1

step "Checking the sound output"
if aplay -l 2>/dev/null | grep -q "card"; then
    ok "Sound cards detected:"
    aplay -l 2>/dev/null | grep '^card' | sed 's/^/    /'
else
    fail "No sound card found. On a Pi this usually means audio is routed to"
    fail "HDMI but nothing is connected, or the audio overlay is disabled."
    fail "See docs/90-speech.md."
fi

step "Checking the action sound"
sound="${ACTION_SOUND:-}"
if [[ -z "$sound" ]]; then
    skip "ACTION_SOUND is empty in config.sh - button beeps disabled"
else
    [[ "$sound" == /* ]] || sound="$REC_ASSETS/sounds/$sound"
    if [[ -f "$sound" ]]; then
        ok "Action sound found: $sound"
    else
        fail "Action sound not found: $sound"
        fail "Fix ACTION_SOUND in config.sh, or set it to \"\" to disable beeps."
    fi
fi

step "Testing speech"
if confirm "Play a test message now?"; then
    if bash "$REC_BIN/speech.sh" "Entertainment centre installed successfully."; then
        ok "Speech works"
    else
        fail "Speech failed. Check the network and the volume - see docs/90-speech.md."
    fi
else
    skip "Skipped. Test later with:"
    note "  bash $REC_BIN/speech.sh \"hello\""
fi

echo
ok "Speech configured."
cat <<EOF

${REC_C_BOLD}Usage${REC_C_OFF}

    bash $REC_BIN/speech.sh "Welcome home"        # uses SPEECH_LANG
    bash $REC_BIN/speech.sh pl "Dzien dobry"      # explicit language

Volume is set by VOLUME (a percentage) in config.sh - currently ${VOLUME:-100}.
It is applied by the player itself, independently of the system mixer, so
turning it down here does not quieten films.
EOF
