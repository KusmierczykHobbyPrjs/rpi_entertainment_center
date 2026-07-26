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

step "Setting the system volume levels"
# Volume here is a chain: Kodi x PipeWire stream x PipeWire sink x ALSA PCM.
# Every stage multiplies, so one link left low makes everything quiet however
# high the others are set. A fresh install commonly leaves ALSA around 40%,
# and the symptom is "volume is at maximum and it is still quiet".
volume_changed=0

if rec_has wpctl; then
    cur="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'Volume: \K[0-9.]+')"
    cur_pct="$(awk -v v="${cur:-0}" 'BEGIN{printf "%d", v*100}')"
    if (( cur_pct >= 90 )); then
        skip "PipeWire sink already at ${cur_pct}%"
    else
        note "PipeWire sink is at ${cur_pct}%"
        if confirm "Raise the PipeWire sink to 100%?"; then
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 100% && ok "Sink set to 100%"
            wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null
            volume_changed=1
        fi
    fi
fi

if rec_has amixer; then
    for ctl in PCM Master Headphone; do
        raw="$(amixer sget "$ctl" 2>/dev/null | grep -oP '\[\K[0-9]+(?=%\])' | head -1)"
        [[ -n "$raw" ]] || continue
        if (( raw >= 90 )); then
            skip "ALSA '$ctl' already at ${raw}%"
        else
            note "ALSA '$ctl' is at ${raw}%"
            if confirm "Raise ALSA '$ctl' to 100%?"; then
                amixer sset "$ctl" 100% >/dev/null && ok "'$ctl' set to 100%"
                volume_changed=1
            fi
        fi
        break
    done
fi

# Without this ALSA forgets the level at the next boot, and the quiet comes
# back with no obvious cause.
if (( volume_changed == 1 )) && rec_has alsactl; then
    if sudo alsactl store 2>/dev/null; then
        ok "Levels saved (persist across reboots)"
    else
        fail "Could not run 'sudo alsactl store' - the level will reset at boot"
    fi
fi

step "Checking the analogue output quality setting"
# The Pi's 3.5 mm jack is PWM through a passive filter, not a DAC.
# audio_pwm_mode=2 selects the better modulation - a real SNR improvement.
BOOTCFG=/boot/firmware/config.txt
[[ -f "$BOOTCFG" ]] || BOOTCFG=/boot/config.txt
if [[ -f "$BOOTCFG" ]] && grep -qi raspberry /proc/device-tree/model 2>/dev/null; then
    if grep -qE '^\s*audio_pwm_mode=2' "$BOOTCFG"; then
        skip "audio_pwm_mode=2 already set"
    else
        note "audio_pwm_mode=2 improves the 3.5 mm jack noticeably."
        if confirm "Add it to $BOOTCFG? (needs a reboot)"; then
            backup_file "$BOOTCFG"
            echo "audio_pwm_mode=2" | sudo tee -a "$BOOTCFG" >/dev/null
            ok "Added - takes effect after a reboot"
        fi
    fi
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

${REC_C_BOLD}If everything is still too quiet${REC_C_OFF}

  The Pi's 3.5 mm jack is PWM through a passive filter, not a DAC - it is
  quiet and noisy by construction. In order of effect:

    - use HDMI audio instead if your TV or receiver can take it:
        sudo raspi-config -> System Options -> Audio -> HDMI
    - amplify in software (clips on loud passages):
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 150%
    - a USB DAC, which fixes both level and noise floor

  Check every stage at once:  $REC_BIN/doctor.sh audio
EOF
