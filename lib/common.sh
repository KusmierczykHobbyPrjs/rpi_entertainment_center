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

# Name of the controlling terminal, e.g. "tty1" or "pts/1"; empty if none.
#
# Deliberately NOT `tty`, which reports the terminal of *stdin*. autostart.sh
# is launched from .bashrc with `&`, and bash redirects an asynchronous
# command's stdin to /dev/null whenever job control is off - which it is while
# startup files are being processed. `tty` therefore prints "not a tty" (in
# the system language, so not even reliably that string) on a perfectly normal
# console login, which made the old console check impossible to satisfy.
#
# The controlling terminal survives that redirection, so ask ps for it. Walk
# up to the parent when this process has none of its own.
rec_controlling_tty() {
    local t
    t="$(ps -o tty= -p "$$" 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "$t" || "$t" == "?" ]]; then
        t="$(ps -o tty= -p "${PPID:-1}" 2>/dev/null | tr -d '[:space:]')"
    fi
    [[ "$t" == "?" ]] && t=""
    printf '%s' "$t"
}

# True when we are running on the physical console rather than over SSH.
rec_on_console() {
    # SSH sets these; cheapest and most reliable negative test.
    [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ]] && return 1

    # systemd/pam set XDG_VTNR to the virtual terminal number on a console
    # login. Trust it when present.
    [[ "${XDG_VTNR:-}" == "1" ]] && return 0

    case "$(rec_controlling_tty)" in
        tty1) return 0 ;;
        tty[0-9]*) return 0 ;;   # any VT counts as console
        *) return 1 ;;
    esac
}

# Which display server this machine will actually use: "wayland", "x11", or
# "unknown".
#
# Note what this does NOT do: infer from installed packages. Raspberry Pi OS
# ships both labwc (rpd-wayland-core) and X (rpd-x-core) by default, so
# "labwc exists" says nothing about what is configured - an earlier version of
# this check warned about Wayland on correctly configured X11 systems.
#
# Order of evidence, most to least reliable.
rec_display_server() {
    # 1. A running session is definitive.
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && { echo wayland; return; }
    case "${XDG_SESSION_TYPE:-}" in
        wayland) echo wayland; return ;;
        x11)     echo x11;     return ;;
    esac

    # 2. A running compositor or X server.
    pgrep -x labwc   >/dev/null 2>&1 && { echo wayland; return; }
    pgrep -x wayfire >/dev/null 2>&1 && { echo wayland; return; }
    pgrep -x Xorg    >/dev/null 2>&1 && { echo x11;     return; }

    # 3. What raspi-config has been told to use. The getter is readable
    #    without sudo on current releases; 0 means Wayland is in use.
    if command -v raspi-config >/dev/null 2>&1; then
        case "$(raspi-config nonint get_wayland 2>/dev/null)" in
            0) echo wayland; return ;;
            1) echo x11;     return ;;
        esac
    fi

    # 4. Give up rather than guess from what happens to be installed.
    echo unknown
}

# True when a UI process is running.
#
# Matching on the exact process name is not enough: what a UI is called in
# `ps` frequently differs from the command that started it. kodi-standalone
# ends up as kodi.bin or kodi-gbm; EmulationStation is truncated to 15
# characters. If the watchdog cannot see a running UI it starts another one
# every few seconds, which looks exactly like "the UI will not start".
#
# So: exact name first (cheap, precise), then a whole-command-line match.
rec_ui_running() {
    local name="$1"
    # stderr is suppressed deliberately: pgrep prints an advisory when the
    # pattern exceeds 15 characters ("pattern that searches for process name
    # longer than 15 characters will not match"), because that is the kernel's
    # comm limit. We already handle that case with the -f fallback below, so
    # the warning is noise - and it would otherwise be printed once per second
    # by the watchdog loop.
    pgrep -x "$name" 2>/dev/null | grep -q . && return 0
    # -f matches the full command line; anchor loosely so kodi matches
    # kodi.bin and kodi-gbm, but not an unrelated process merely mentioning it.
    pgrep -f "(^|/)${name}" >/dev/null 2>&1 && return 0
    return 1
}

# Stop a UI by process name, coping with names longer than 15 characters.
#
# `pkill -x` matches against the kernel's comm field, which is truncated to 15
# characters - so `pkill -x kodi-standalone-x` silently matches nothing and the
# force-kill escalation does nothing at all. Fall back to a command-line match.
rec_ui_kill() {
    local name="$1" sig="${2:-}"
    if (( ${#name} <= 15 )); then
        pkill ${sig:+"$sig"} -x "$name" 2>/dev/null && return 0
    fi
    pkill ${sig:+"$sig"} -f "(^|/)${name}" 2>/dev/null
}

# Convert a 0-100 volume percentage into the 0-32768 scale mpg123 -f expects.
rec_volume_scale() {
    local pct="${VOLUME:-100}"
    echo $(( pct * 32768 / 100 ))
}
