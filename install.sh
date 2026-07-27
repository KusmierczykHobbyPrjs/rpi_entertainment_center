#!/bin/bash
# ---------------------------------------------------------------------------
# install.sh - install the entertainment centre, one module at a time.
#
#   ./install.sh                 interactive menu (recommended first time)
#   ./install.sh --list          show every module and whether it is installed
#   ./install.sh 00-base 10-kodi install specific modules, in the order given
#   ./install.sh --all           install every module
#   ./install.sh --all --yes     unattended: assume "yes" to every prompt
#
# Modules are independent and idempotent: re-running one is always safe, and
# you only install the parts you actually want. The numeric prefixes are the
# recommended order, because later modules assume earlier ones are present
# (everything assumes 00-base).
#
# See INSTALL.md for the full walkthrough.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/lib/install_helpers.sh"

require_not_root

# Modules in their recommended install order, with a one-line description.
# Keep this list in sync with modules/ and docs/.
declare -a MODULES=(
    "00-base|Core packages, config file, console autologin, autostart hook"
    "10-kodi|Kodi media centre plus streaming and joystick support"
    "15-kodi-iptv|Live TV and radio over IPTV (PVR IPTV Simple Client)"
    "20-kodi-addons|Bundled Kodi add-ons: YouTube, TVP VOD, Yle, Shell Launcher"
    "25-tvheadend|Tvheadend DVB/TV backend and its Kodi client"
    "30-retropie|RetroPie retro gaming front-end (EmulationStation)"
    "40-desktop|The shipped desktop as the third UI, plus Chromium"
    "45-kdeconnect|Control the desktop from a phone with KDE Connect"
    "50-ui-rotation|Switch between Kodi / RetroPie / Desktop with one button"
    "60-gpio|Physical push buttons wired to GPIO pins"
    "70-nordvpn|NordVPN with Meshnet, rotation and spoken status"
    "75-port-forwarding|Expose LAN devices (IP camera, NAS) through this Pi"
    "80-webserver|Apache + PHP reachable worldwide via No-IP and HTTPS"
    "85-bluetooth|Use the Pi as a Bluetooth speaker (phone -> Pi -> jack)"
    "90-speech|Spoken status messages and the action beep"
    "95-weather|Spoken weather reports, in the configured language"
)

module_id()   { echo "${1%%|*}"; }
module_desc() { echo "${1#*|}"; }

usage() {
    sed -n '3,20p' "$(readlink -f "$0")" | sed 's/^# \{0,1\}//'
    exit 0
}

list_modules() {
    printf '%s%-20s %-9s %s%s\n' "$REC_C_BOLD" "MODULE" "STATE" "DESCRIPTION" "$REC_C_OFF"
    local entry id desc state
    for entry in "${MODULES[@]}"; do
        id="$(module_id "$entry")"
        desc="$(module_desc "$entry")"
        if [[ -f "$REC_ROOT/.installed/$id" ]]; then
            state="${REC_C_GREEN}installed${REC_C_OFF}"
        else
            state="${REC_C_YELLOW}not yet  ${REC_C_OFF}"
        fi
        # %s (not %b) because the colour codes are already literal escapes;
        # the padding is baked into the state strings so both are 9 columns.
        printf '%-20s %s %s\n' "$id" "$state" "$desc"
    done
}

run_module() {
    local id="$1"
    local script="$REC_MODULES/$id/install.sh"

    if [[ ! -f "$script" ]]; then
        fail "Unknown module: $id  (try ./install.sh --list)"
        return 1
    fi

    echo
    printf '%s========================================================%s\n' "$REC_C_BOLD" "$REC_C_OFF"
    printf '%s  %s%s\n' "$REC_C_BOLD" "$id" "$REC_C_OFF"
    printf '%s========================================================%s\n' "$REC_C_BOLD" "$REC_C_OFF"

    if bash "$script"; then
        mkdir -p "$REC_ROOT/.installed"
        date -Iseconds > "$REC_ROOT/.installed/$id"
        ok "Module $id finished."
        return 0
    fi

    fail "Module $id failed. Fix the problem above and re-run: ./install.sh $id"
    return 1
}

interactive_menu() {
    cat <<EOF

${REC_C_BOLD}Raspberry Pi Entertainment Centre - installer${REC_C_OFF}

Pick the modules you want. Everything depends on 00-base, so install that
first. You can re-run this installer at any time to add more modules.

EOF
    local entry id desc i=1
    for entry in "${MODULES[@]}"; do
        id="$(module_id "$entry")"
        desc="$(module_desc "$entry")"
        if [[ -f "$REC_ROOT/.installed/$id" ]]; then
            printf '  %2d) %-20s %s(installed)%s %s\n' "$i" "$id" "$REC_C_GREEN" "$REC_C_OFF" "$desc"
        else
            printf '  %2d) %-20s %s\n' "$i" "$id" "$desc"
        fi
        i=$((i + 1))
    done

    cat <<EOF

  a) everything, in order
  q) quit

EOF
    local reply
    read -r -p "Modules to install (e.g. '1 2 5', 'a', or 'q'): " -a reply

    local selection=()
    local choice
    for choice in "${reply[@]}"; do
        case "$choice" in
            q|Q) echo "Nothing installed."; exit 0 ;;
            a|A) for entry in "${MODULES[@]}"; do selection+=("$(module_id "$entry")"); done ;;
            [0-9]*)
                if (( choice >= 1 && choice <= ${#MODULES[@]} )); then
                    selection+=("$(module_id "${MODULES[$((choice - 1))]}")")
                else
                    fail "Ignoring out-of-range choice: $choice"
                fi
                ;;
            *) fail "Ignoring unrecognised choice: $choice" ;;
        esac
    done

    if [[ ${#selection[@]} -eq 0 ]]; then
        echo "Nothing selected."
        exit 0
    fi

    printf '%s\n' "${selection[@]}"
}

# --- Argument handling -----------------------------------------------------

declare -a to_install=()

if [[ $# -eq 0 ]]; then
    mapfile -t to_install < <(interactive_menu)
else
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)  usage ;;
            -l|--list)  list_modules; exit 0 ;;
            -y|--yes)   export REC_ASSUME_YES=1 ;;
            -a|--all)
                for entry in "${MODULES[@]}"; do to_install+=("$(module_id "$entry")"); done
                ;;
            -*) fail "Unknown option: $1"; usage ;;
            *)  to_install+=("$1") ;;
        esac
        shift
    done
fi

if [[ ${#to_install[@]} -eq 0 ]]; then
    echo "Nothing to do."
    exit 0
fi

# --- Run -------------------------------------------------------------------

warn_if_not_pi

declare -a failed=()
for id in "${to_install[@]}"; do
    run_module "$id" || failed+=("$id")
done

echo
printf '%s========================================================%s\n' "$REC_C_BOLD" "$REC_C_OFF"
if [[ ${#failed[@]} -eq 0 ]]; then
    ok "All selected modules installed."
    echo
    echo "Next steps:"
    echo "  1. Review your settings:   nano $REC_ROOT/config.sh"
    echo "  2. Check everything works: $REC_ROOT/bin/doctor.sh"
    echo "  3. Reboot:                 sudo reboot"
else
    fail "These modules failed: ${failed[*]}"
    echo "Re-run them individually after fixing the errors above:"
    echo "  ./install.sh ${failed[*]}"
    exit 1
fi
