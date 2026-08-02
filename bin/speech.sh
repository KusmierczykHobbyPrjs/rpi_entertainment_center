#!/bin/bash
# ---------------------------------------------------------------------------
# speech.sh - speak a line of text through the TV speakers.
#
# Uses the free Google Translate text-to-speech endpoint, so it needs an
# internet connection but no API key and no local voice data (which matters on
# a Pi 3B, where espeak sounds poor and larger engines are too slow).
#
#   speech.sh "Welcome home"          speak in $SPEECH_LANG (default: en)
#   speech.sh pl "Dzien dobry"        speak in a specific language
#
# THE LANGUAGE ARGUMENT DESCRIBES THE TEXT, IT IS NOT A PREFERENCE. The voice
# has to match the words, or a Polish synthesiser ends up reading English and
# sounds broken. So:
#
#   - text fixed in the source (the VPN messages, the install test) passes its
#     own language explicitly, always "en";
#   - text generated in the user's language (weather.py, which asks for
#     translated descriptions and has per-language sentence templates) passes
#     $SPEECH_LANG, because that is genuinely what it was written in.
#
# Omitting the code means "this text is in $SPEECH_LANG" - only correct for
# text you produced in that language.
#
# The endpoint rejects long strings, so the text is split into <=150 character
# chunks by speech_text_splitter.py and played back in order.
#
# See docs/90-speech.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

MAX_LENGTH=150
TTS_ENDPOINT="http://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob"

if ! rec_has mpg123; then
    rec_error "mpg123 is not installed. Run: sudo apt-get install mpg123"
    exit 1
fi

# Speaking requires the network. Without this check, every message issued
# while the network is still coming up (VPN status at boot, most commonly)
# produced a page of mpg123 resolver errors and no sound at all.
if ! rec_online; then
    rec_warn "No internet connection - cannot synthesise speech. Text was: $*"
    exit 0
fi

# First argument is a language code only if it looks like one.
VALID_LANG_CODES="af ar az be bg bn bs ca cs cy da de el en es et eu fa fi fr \
gl gu he hi hr ht hu hy id is it ja ka kn ko la lt lv mk ml mr ms mt nl no pl \
pt ro ru sk sl sq sr sv sw ta te th tl tr uk ur vi zh"

LANG_CODE="${SPEECH_LANG:-en}"
if [[ $# -gt 1 ]] && [[ " $VALID_LANG_CODES " == *" $1 "* ]]; then
    LANG_CODE="$1"
    shift
fi

INPUT="$*"
[[ -n "$INPUT" ]] || { rec_warn "Nothing to say."; exit 0; }

VOLUME_SCALE="$(rec_volume_scale)"

# Split into endpoint-sized chunks, then percent-encode each one. Encoding is
# done with python3 (already required by the splitter) rather than xxd, which
# is packaged differently across Raspberry Pi OS releases.
while IFS= read -r part; do
    [[ -n "$part" ]] || continue
    encoded="$(python3 -c \
        'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' \
        "$part")"
    rec_log "Speaking [$LANG_CODE]: $part"
    mpg123 -q -b 100 -f "$VOLUME_SCALE" \
        "${TTS_ENDPOINT}&q=${encoded}&tl=${LANG_CODE}" \
        || rec_warn "Playback failed for this segment."
done < <(python3 "$REC_BIN/speech_text_splitter.py" "$MAX_LENGTH" "$INPUT")
