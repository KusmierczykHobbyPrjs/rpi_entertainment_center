#!/bin/bash
# ---------------------------------------------------------------------------
# signal_action.sh - play the short "command received" beep.
#
# Called by anything triggered from a button or a phone, where the visible
# effect (VPN reconnect, UI switch) takes several seconds. Without immediate
# audible feedback those actions feel like they did nothing.
#
# The sound file is set by $ACTION_SOUND in config.sh; a bare filename is
# looked up in assets/sounds/. Set ACTION_SOUND="" to disable.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

[[ -n "${ACTION_SOUND:-}" ]] || exit 0

# Resolve a bare filename against the bundled sounds directory.
sound="$ACTION_SOUND"
if [[ "$sound" != /* ]]; then
    sound="$REC_ASSETS/sounds/$sound"
fi

if [[ ! -f "$sound" ]]; then
    rec_warn "Action sound not found: $sound"
    exit 0
fi

rec_has mpg123 || exit 0

mpg123 -q -b 100 -f "$(rec_volume_scale)" "$sound"
