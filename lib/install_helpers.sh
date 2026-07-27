#!/bin/bash
# ---------------------------------------------------------------------------
# install_helpers.sh - shared helpers for the module installers.
#
# Every helper here is idempotent: running an installer twice must be safe and
# must not duplicate lines in config files. Installers source this file, never
# the other way round.
# ---------------------------------------------------------------------------

REC_SKIP_CONFIG=1
# shellcheck source=./common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

# --- Pretty output ---------------------------------------------------------
if [[ -t 1 ]]; then
    REC_C_BOLD=$'\033[1m'; REC_C_GREEN=$'\033[32m'; REC_C_YELLOW=$'\033[33m'
    REC_C_RED=$'\033[31m'; REC_C_BLUE=$'\033[34m'; REC_C_OFF=$'\033[0m'
else
    REC_C_BOLD=""; REC_C_GREEN=""; REC_C_YELLOW=""
    REC_C_RED=""; REC_C_BLUE=""; REC_C_OFF=""
fi

step()  { printf '%s==>%s %s%s%s\n' "$REC_C_BLUE" "$REC_C_OFF" "$REC_C_BOLD" "$*" "$REC_C_OFF"; }
ok()    { printf '  %s[ok]%s %s\n'   "$REC_C_GREEN"  "$REC_C_OFF" "$*"; }
skip()  { printf '  %s[--]%s %s\n'   "$REC_C_YELLOW" "$REC_C_OFF" "$*"; }
note()  { printf '  %s[..]%s %s\n'   "$REC_C_BLUE"   "$REC_C_OFF" "$*"; }
fail()  { printf '  %s[!!]%s %s\n'   "$REC_C_RED"    "$REC_C_OFF" "$*" >&2; }

# --- Guards ----------------------------------------------------------------

# Refuse to run installers as root. They use sudo where needed; running the
# whole thing as root would create root-owned files in the user's home.
require_not_root() {
    if [[ $EUID -eq 0 ]]; then
        fail "Do not run this installer with sudo or as root."
        fail "It calls sudo itself for the few steps that need it."
        exit 1
    fi
}

# Warn (but do not stop) when running on something that is not a Raspberry Pi,
# so the scripts stay usable for testing on a normal Debian box.
warn_if_not_pi() {
    if ! grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
        skip "This does not look like a Raspberry Pi - hardware steps may fail."
    fi
}

# --- Package installation --------------------------------------------------

REC_APT_UPDATED=0

apt_refresh() {
    if [[ $REC_APT_UPDATED -eq 0 ]]; then
        note "Refreshing package lists (sudo apt-get update)"
        sudo apt-get update -qq
        REC_APT_UPDATED=1
    fi
}

# apt_install pkg [pkg...] - installs only the packages that are missing.
apt_install() {
    local missing=()
    local pkg
    for pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            skip "$pkg already installed"
        else
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    apt_refresh
    note "Installing: ${missing[*]}"
    if sudo apt-get install -y "${missing[@]}"; then
        ok "Installed: ${missing[*]}"
    else
        fail "Failed to install: ${missing[*]}"
        return 1
    fi
}

# --- File editing ----------------------------------------------------------

# backup_file PATH - copies PATH to PATH.rec-backup once, never overwriting an
# existing backup, so the very first (pristine) version is what you can revert
# to no matter how many times an installer runs.
backup_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    if [[ ! -f "${path}.rec-backup" ]]; then
        sudo cp -a "$path" "${path}.rec-backup" 2>/dev/null \
            || cp -a "$path" "${path}.rec-backup"
        note "Backed up $path -> ${path}.rec-backup"
    fi
}

# ensure_line FILE LINE - appends LINE to FILE unless an identical line is
# already present. Uses sudo transparently when FILE is not writable.
ensure_line() {
    local file="$1" line="$2"

    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        skip "Already present in $file: $line"
        return 0
    fi

    backup_file "$file"
    if [[ -w "$file" ]] || [[ ! -e "$file" && -w "$(dirname "$file")" ]]; then
        printf '%s\n' "$line" >> "$file"
    else
        printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null
    fi
    ok "Added to $file: $line"
}

# ensure_block FILE MARKER CONTENT - maintains a marker-delimited block inside
# FILE. Re-running replaces the block instead of appending a second copy, which
# is what makes the autostart and GPIO installers safely repeatable.
ensure_block() {
    local file="$1" marker="$2" content="$3"
    local begin="# >>> ${marker} >>>"
    local end="# <<< ${marker} <<<"
    local tmp
    tmp="$(mktemp)"

    if [[ -f "$file" ]]; then
        backup_file "$file"
        # Strip any previous copy of the block.
        awk -v b="$begin" -v e="$end" '
            $0 == b { inblock = 1; next }
            $0 == e { inblock = 0; next }
            !inblock { print }
        ' "$file" > "$tmp"
    fi

    {
        printf '%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
    } >> "$tmp"

    if [[ -w "$file" ]] || [[ ! -e "$file" && -w "$(dirname "$file")" ]]; then
        cat "$tmp" > "$file"
    else
        sudo cp "$tmp" "$file"
    fi
    rm -f "$tmp"
    ok "Updated '${marker}' block in $file"
}

# --- Interaction -----------------------------------------------------------

# confirm "Question?" - returns 0 for yes. Auto-answers yes when the installer
# runs with REC_ASSUME_YES=1 (used by `install.sh --all --yes`).
confirm() {
    local prompt="$1" reply
    if [[ "${REC_ASSUME_YES:-0}" == "1" ]]; then
        return 0
    fi
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# --- Groups ----------------------------------------------------------------

# Set to 1 by ensure_group when a membership only applies after re-login.
REC_GROUP_PENDING=0

# Make $USER a member of a group and report honestly whether it is usable yet.
#
# Returns 0 when the CURRENT session already has it, 1 when it will only take
# effect after logging out and back in. Callers should skip steps that would
# fail in that case rather than emitting a wall of permission errors.
ensure_group() {
    local grp="$1"

    if ! getent group "$grp" >/dev/null 2>&1; then
        skip "Group '$grp' does not exist on this system"
        return 0
    fi

    if rec_in_group "$grp"; then
        skip "$USER is in '$grp' (active in this session)"
        return 0
    fi

    if rec_group_configured "$grp"; then
        skip "$USER is in '$grp' in the group database"
    else
        sudo usermod -a -G "$grp" "$USER" \
            && ok "Added $USER to '$grp'" \
            || { fail "Could not add $USER to '$grp'"; return 1; }
    fi

    fail "...but this session does not have '$grp' yet."
    note "Group membership only applies at the next login. Log out and back in"
    note "(or reboot), then re-run this module."
    REC_GROUP_PENDING=1
    return 1
}

# --- Config bootstrap ------------------------------------------------------

# Creates config.sh from the template on first run.
ensure_config() {
    if [[ -f "$REC_ROOT/config.sh" ]]; then
        skip "config.sh already exists (not overwriting)"
    else
        cp "$REC_ROOT/config.example.sh" "$REC_ROOT/config.sh"
        chmod 600 "$REC_ROOT/config.sh"
        ok "Created config.sh from config.example.sh"
        note "Edit it before relying on VPN or port forwarding: nano $REC_ROOT/config.sh"
    fi
}
