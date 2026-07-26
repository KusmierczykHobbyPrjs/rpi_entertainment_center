#!/bin/bash
# ---------------------------------------------------------------------------
# common.sh - shared runtime library for every script in this project.
#
# Sourcing this file gives a script:
#   $REC_ROOT   absolute path to the repository root (works from any cwd)
#   $REC_BIN    absolute path to bin/
#   $REC_ASSETS absolute path to assets/
#   the user's configuration, already loaded from config.sh
#   logging helpers, a single-instance lock helper and a rate-limit helper
#
# Every script starts with the same three lines, and nothing here depends on
# the repository living in a particular directory:
#
#     #!/bin/bash
#     source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
#
# ---------------------------------------------------------------------------

# --- Locate the repository root -------------------------------------------
# BASH_SOURCE[0] is this file even when it is sourced, so the root is always
# one directory above lib/ - regardless of the caller's working directory.
REC_LIB_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REC_ROOT="$(dirname "$REC_LIB_DIR")"
REC_BIN="$REC_ROOT/bin"
REC_ASSETS="$REC_ROOT/assets"
REC_MODULES="$REC_ROOT/modules"
export REC_ROOT REC_BIN REC_ASSETS REC_MODULES

# --- Logging ---------------------------------------------------------------
# Tag every line with the calling script so that a shared journal/log stays
# readable when several background scripts write to it at once.
REC_TAG="$(basename "${0:-rec}")"

rec_log()   { printf '[%s] %s\n' "$REC_TAG" "$*"; }
rec_warn()  { printf '[%s] WARNING: %s\n' "$REC_TAG" "$*" >&2; }
rec_error() { printf '[%s] ERROR: %s\n' "$REC_TAG" "$*" >&2; }
rec_die()   { rec_error "$*"; exit 1; }

# --- Configuration ---------------------------------------------------------
# config.sh holds machine-specific settings and secrets and is NOT in git.
# config.example.sh is the tracked template.
rec_load_config() {
    local cfg="$REC_ROOT/config.sh"

    # Anything already set in the environment beats config.sh, so a single run
    # can be overridden without editing the file:
    #
    #     VOLUME=0 SPEECH_LANG=pl bash bin/say_weather.sh
    #
    # Sourcing alone would not do this - config.sh assigns unconditionally and
    # would silently overwrite the caller's value. So the exported environment
    # is snapshotted first and re-applied afterwards. Arrays (REC_UI_*,
    # REC_GPIO_BUTTONS) are not exported and so are unaffected.
    # `export -p` prints "declare -x VAR=...", and `declare` inside a function
    # creates a *local* - so replaying it verbatim would set a variable that
    # vanishes when this function returns. Rewriting it to `export` assigns
    # the global, which is what we need.
    local rec_saved_env
    rec_saved_env="$(export -p | sed 's/^declare -x /export /')"

    if [[ -f "$cfg" ]]; then
        # shellcheck source=/dev/null
        source "$cfg"
        eval "$rec_saved_env" 2>/dev/null
        return
    else
        rec_warn "config.sh not found. Copy config.example.sh to config.sh and edit it."
        rec_warn "Falling back to the defaults in config.example.sh."
        # shellcheck source=/dev/null
        source "$REC_ROOT/config.example.sh"
        eval "$rec_saved_env" 2>/dev/null
    fi
}

# Scripts that only need helpers (installers) can set REC_SKIP_CONFIG=1.
if [[ "${REC_SKIP_CONFIG:-0}" != "1" ]]; then
    rec_load_config
fi

# --- Single-instance lock --------------------------------------------------
# Uses flock so the lock is released by the kernel even if the script is
# SIGKILLed. The previous stale-file approach left locks behind after a hard
# reboot, which silently stopped the UI watchdog from ever starting again.
#
# Usage:  rec_single_instance || exit 0
rec_single_instance() {
    local name="${1:-$REC_TAG}"
    local lockfile="/run/lock/rec-${name}.lock"

    # /run/lock is tmpfs on Raspberry Pi OS; fall back to /tmp if unavailable.
    [[ -d /run/lock && -w /run/lock ]] || lockfile="/tmp/rec-${name}.lock"

    exec {REC_LOCK_FD}>"$lockfile" || return 1
    if ! flock -n "$REC_LOCK_FD"; then
        return 1   # another copy already holds the lock
    fi
    return 0
}

# --- Rate limiting ---------------------------------------------------------
# Physical buttons bounce and phone apps double-tap. rec_rate_limit exits the
# script when it was last run less than N seconds ago.
#
# Usage:  rec_rate_limit 5
rec_rate_limit() {
    local delay_seconds="${1:-5}"
    local stamp="/tmp/rec-${REC_TAG}.timestamp"
    local now last

    now="$(date +%s)"
    if [[ -f "$stamp" ]]; then
        last="$(cat "$stamp" 2>/dev/null || echo 0)"
        if (( now - last < delay_seconds )); then
            exit 0
        fi
    fi
    echo "$now" > "$stamp"
}

# --- Misc helpers ----------------------------------------------------------

# True when a command exists.
#
# Also searches /sbin and /usr/sbin explicitly: on Raspberry Pi OS those are
# not on a normal user's PATH, so `command -v` alone reports system binaries
# like `shutdown`, `apache2` and `ss` as missing when they are installed.
rec_has() {
    command -v "$1" >/dev/null 2>&1 && return 0
    local dir
    for dir in /sbin /usr/sbin /usr/local/sbin; do
        [[ -x "$dir/$1" ]] && return 0
    done
    return 1
}

# True when there is a usable route to the internet. Used to skip actions
# (like the Google-Translate speech synthesis) that would otherwise emit a
# wall of resolver errors while the network is still coming up.
rec_online() {
    ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}

# Convert a 0-100 volume percentage into the 0-32768 scale mpg123 -f expects.
rec_volume_scale() {
    local pct="${VOLUME:-100}"
    echo $(( pct * 32768 / 100 ))
}
