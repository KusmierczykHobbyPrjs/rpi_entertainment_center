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

# --- Firewall --------------------------------------------------------------
#
# Only 80-webserver turns ufw on, and it is usually the LAST module installed.
# By then Kodi, Tvheadend, KDE Connect and Meshnet are already running, and a
# default-deny policy silently cuts every one of them off: phone remotes stop
# connecting, `kodi-send` stops working, Meshnet peers can no longer reach the
# Pi. Nothing errors - things just quietly stop.
#
# Modules installed AFTER ufw open their own ports (45-kdeconnect and
# 75-port-forwarding both check `ufw status`). These helpers cover the other
# direction: a module installed BEFORE ufw existed. Detection is by what is
# actually present on the machine, not by which modules were chosen, so the
# install order stops mattering either way.

# True when ufw is installed and its policy is being enforced.
ufw_active() {
    rec_has ufw && sudo ufw status 2>/dev/null | grep -q "Status: active"
}

# Every directly-attached IPv4 network, one CIDR per line - "192.168.1.0/24".
#
# Taken from the kernel's own link-scope routes, so it works on any interface
# name (eth0, wlan0, wlp3s0, end0) and any subnet, rather than assuming the
# 192.168.1.0/24 this happened to be written on.
#
# VPN and container interfaces are excluded: a Meshnet peer is not "the LAN",
# and 100.64.0.0/10 is shared with every other NordVPN user in the world.
# Meshnet gets its own interface rule below instead.
rec_lan_cidrs() {
    ip -o -4 route show scope link 2>/dev/null | awk '
        $3 ~ /^(lo|nordlynx|nordtun|tun|tap|wg|docker|veth|br-)/ { next }
        $1 ~ /^(169\.254\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)/ { next }
        { print $1 }' | sort -u
}

# ufw_allow_lan PORT[:PORT]/PROTO "comment" - reachable from the local network
# only, never from the internet.
#
# This distinction is the whole point. Kodi's web interface and JSON-RPC have
# no authentication worth the name; a bare `ufw allow 8080/tcp` would publish
# them the moment a port-forwarding rule is added to the router. Scoping to the
# LAN keeps the phone remotes working with no such exposure.
ufw_allow_lan() {
    local rule="$1" comment="$2"
    local port="${rule%%/*}" proto="${rule##*/}"
    local cidr found=0

    while IFS= read -r cidr; do
        [[ -n "$cidr" ]] || continue
        found=1
        sudo ufw allow from "$cidr" to any port "$port" proto "$proto" \
            comment "$comment" >/dev/null 2>&1
    done < <(rec_lan_cidrs)

    if (( found )); then
        ok "  $comment - $port/$proto from the local network"
    else
        # Opening it to the whole internet instead would be a silent security
        # downgrade, so say what is wrong and let the user decide.
        fail "  $comment - could not determine the LAN, left CLOSED"
        note "    Open it by hand: sudo ufw allow from <your-lan>/24 to any port $port proto $proto"
    fi
}

# ufw_allow_iface IFACE "comment" - trust everything arriving on one interface.
# Used for Meshnet, where the peers are authenticated by WireGuard before a
# packet ever reaches the firewall.
ufw_allow_iface() {
    local iface="$1" comment="$2"
    ip link show "$iface" >/dev/null 2>&1 || return 1
    sudo ufw allow in on "$iface" comment "$comment" >/dev/null 2>&1
    ok "  $comment - everything arriving on $iface"
}

# Re-open the ports belonging to whatever else this project has installed.
# Safe to run repeatedly: ufw skips rules it already has.
rec_ufw_open_project_services() {
    if ! ufw_active; then
        skip "ufw is not active - nothing to open"
        return 0
    fi

    # Kodi: web interface + JSON-RPC over HTTP (8080), raw JSON-RPC (9090) and
    # the EventServer that `kodi-send` and most remotes use (9777/udp).
    # Checked on disk rather than with pgrep, because Kodi is frequently not
    # running while a module installs.
    if rec_has kodi || [[ -d "$HOME/.kodi" ]]; then
        ufw_allow_lan 8080/tcp "Kodi web interface"
        ufw_allow_lan 9090/tcp "Kodi JSON-RPC"
        ufw_allow_lan 9777/udp "Kodi EventServer"
    fi

    # Tvheadend: web interface (9981) and the HTSP stream protocol its clients
    # use (9982).
    if rec_has tvheadend || systemctl list-unit-files 2>/dev/null | grep -q '^tvheadend'; then
        ufw_allow_lan 9981/tcp "Tvheadend web interface"
        ufw_allow_lan 9982/tcp "Tvheadend HTSP"
    fi

    # KDE Connect picks a free port in this range per device, so the whole
    # range has to be open for pairing to complete.
    if rec_has kdeconnect-cli || rec_has kdeconnectd; then
        ufw_allow_lan 1714:1764/tcp "KDE Connect"
        ufw_allow_lan 1714:1764/udp "KDE Connect"
    fi

    # Samba - how RetroPie ROMs are usually copied over the network.
    if rec_has smbd; then
        ufw_allow_lan 445/tcp "Samba"
        ufw_allow_lan 139/tcp "Samba (NetBIOS)"
        ufw_allow_lan 137:138/udp "Samba (NetBIOS name service)"
    fi

    # mDNS, which is what makes <hostname>.local resolve and lets phone apps
    # find the Pi without being told its address.
    if rec_has avahi-daemon; then
        ufw_allow_lan 5353/udp "mDNS / Avahi discovery"
    fi

    # Meshnet (70-nordvpn) is the recommended way to reach the Pi from outside,
    # and is the one thing here that must keep working from off the LAN.
    ufw_allow_iface nordlynx "NordVPN Meshnet" \
        || skip "  Meshnet is not set up - no nordlynx rule needed"

    # Ports this Pi forwards on to another device (75-port-forwarding). Read
    # from config.sh, which installers do not load by default.
    if [[ -z "${REC_PORT_FORWARDS+x}" && -f "$REC_ROOT/config.sh" ]]; then
        # shellcheck source=/dev/null
        source "$REC_ROOT/config.sh" 2>/dev/null
    fi
    local entry listen_port
    for entry in "${REC_PORT_FORWARDS[@]:-}"; do
        [[ -n "$entry" ]] || continue
        IFS=':' read -r listen_port _ _ <<<"$entry"
        [[ "$listen_port" =~ ^[0-9]+$ ]] || continue
        ufw_allow_lan "$listen_port/tcp" "rec port forward"
    done

    # Record that this ran. doctor.sh cannot read /etc/ufw/user.rules - it is
    # root-only and doctor.sh deliberately never calls sudo - so this
    # world-readable stamp is how it tells "ufw on, ports opened" apart from
    # "ufw on, everything still blocked".
    sudo mkdir -p "$(dirname "$REC_UFW_STAMP")" 2>/dev/null
    date -Is | sudo tee "$REC_UFW_STAMP" >/dev/null 2>&1
    sudo chmod 644 "$REC_UFW_STAMP" 2>/dev/null
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
