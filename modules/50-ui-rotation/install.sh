#!/bin/bash
# ---------------------------------------------------------------------------
# 50-ui-rotation - one button, three environments.
#
# There is nothing to compile here: the rotation is two scripts plus the list
# of UIs in config.sh. What this module does is check that the UIs you listed
# actually exist, and trim the ones that do not - a mismatch here is the
# usual cause of "the screen goes black and never comes back".
#
# See docs/50-ui-rotation.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# This module needs the user's real config, not just the helpers.
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"
rec_load_config

require_not_root

step "Installing flock (used to keep one watchdog running)"
apt_install util-linux || exit 1

step "Checking the configured UIs"
# Each UI is a (process, name, start, stop) tuple in config.sh. Verify the
# start command's binary is actually installed.
missing=()
for i in "${!REC_UI_NAMES[@]}"; do
    name="${REC_UI_NAMES[$i]}"
    start_cmd="${REC_UI_START[$i]}"
    binary="${start_cmd%% *}"

    if rec_has "$binary"; then
        ok "$name -> $binary (found)"
    else
        fail "$name -> $binary (NOT installed)"
        missing+=("$name")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo
    fail "These UIs are configured but not installed: ${missing[*]}"
    cat <<EOF

The watchdog would try to start them, fail, and leave the screen blank.
Fix it either by installing the missing module:

    ./install.sh 10-kodi        # Kodi
    ./install.sh 30-retropie    # RetroPie / EmulationStation
    ./install.sh 40-desktop     # LXDE desktop

or by removing that UI from all four arrays in config.sh
(REC_UI_PROCESSES, REC_UI_NAMES, REC_UI_START, REC_UI_STOP - they are
parallel, so remove the same index from each).

EOF
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

step "Checking the array lengths match"
# The four arrays are indexed together; a mismatch produces an unbound
# variable at the worst possible moment (mid-switch, with no UI running).
n=${#REC_UI_PROCESSES[@]}
if [[ ${#REC_UI_NAMES[@]} -ne $n || ${#REC_UI_START[@]} -ne $n || ${#REC_UI_STOP[@]} -ne $n ]]; then
    fail "The UI arrays in config.sh have different lengths:"
    fail "  REC_UI_PROCESSES: ${#REC_UI_PROCESSES[@]}"
    fail "  REC_UI_NAMES:     ${#REC_UI_NAMES[@]}"
    fail "  REC_UI_START:     ${#REC_UI_START[@]}"
    fail "  REC_UI_STOP:      ${#REC_UI_STOP[@]}"
    fail "All four must have the same number of entries."
    exit 1
fi
ok "All four UI arrays have $n entries"

step "Checking the default UI index"
if (( REC_UI_DEFAULT_INDEX < 0 || REC_UI_DEFAULT_INDEX >= n )); then
    fail "REC_UI_DEFAULT_INDEX=$REC_UI_DEFAULT_INDEX is out of range (0-$((n - 1)))"
    exit 1
fi
ok "Default UI on boot: ${REC_UI_NAMES[$REC_UI_DEFAULT_INDEX]}"

step "Confirming the autostart hook is in place"
if grep -q "rpi-entertainment-center" "$HOME/.bashrc" 2>/dev/null; then
    ok "autostart.sh is hooked into ~/.bashrc"
else
    fail "autostart.sh is not hooked into ~/.bashrc - run: ./install.sh 00-base"
    exit 1
fi

echo
ok "UI rotation configured."
cat <<EOF

${REC_C_BOLD}How to switch${REC_C_OFF}

  - press the GPIO button wired for it (module 60-gpio), or
  - use "Switch UI" in the Kodi Shell Script Launcher menu, or
  - over SSH:  $REC_BIN/stop_current_ui.sh

Rotation order: ${REC_UI_NAMES[*]} (then back to the start).

${REC_C_BOLD}Test it without rebooting${REC_C_OFF}

  REC_FORCE_AUTOSTART=1 bash $REC_BIN/autostart.sh

Only do that from the physical console - over SSH it will try to start a UI
on a screen you cannot see.
EOF
