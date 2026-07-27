#!/bin/bash
# ---------------------------------------------------------------------------
# diagnose.sh - collect everything needed to work out why a UI is not starting.
#
#   bin/diagnose.sh                 print a report
#   bin/diagnose.sh --try           also try to start the default UI and
#                                   capture whatever it prints (run this from
#                                   the PHYSICAL CONSOLE, not over SSH)
#
# The output is meant to be pasted somewhere. It contains no secrets: the
# config dump is filtered to UI settings only.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

TRY=0
[[ "${1:-}" == "--try" ]] && TRY=1

hr() { printf '\n===== %s =====\n' "$1"; }

hr "SYSTEM"
grep PRETTY_NAME /etc/os-release
echo "arch:     $(uname -m)"
model="$( { tr -d '\0' < /proc/device-tree/model; } 2>/dev/null )"
echo "model:    ${model:-not a Raspberry Pi}"
echo "uptime:   booted $(uptime -s)"
echo "repo:     $REC_ROOT"
echo "user:     $USER"
echo "tty:      $(tty 2>/dev/null || true)"
echo "session:  ${XDG_SESSION_TYPE:-unset}   WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}   DISPLAY=${DISPLAY:-unset}"

hr "BOOT CONFIGURATION"
echo "default target:  $(systemctl get-default 2>&1)"
echo -n "tty1 autologin:  "
[[ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]] && echo present || echo MISSING
for dm in lightdm gdm3 sddm greetd; do
    printf 'display manager %-8s %s\n' "$dm" "$(systemctl is-enabled $dm 2>&1)"
done
echo -n ".bashrc hook:    "
grep -q 'rpi-entertainment-center' "$HOME/.bashrc" 2>/dev/null && echo present || echo MISSING
echo -n ".profile sources .bashrc: "
grep -q 'bashrc' "$HOME/.profile" 2>/dev/null && echo yes || echo "NO (autostart will never run on a login shell)"

hr "GROUPS"
echo "member of: $(id -nG)"
for grp in video render input tty audio; do
    printf '  %-8s %s\n' "$grp" "$(id -nG | grep -qw "$grp" && echo yes || echo NO)"
done

hr "UI CONFIGURATION"
for i in "${!REC_UI_NAMES[@]}"; do
    printf '%d  %-10s process=%-18s start=%s\n' \
        "$i" "${REC_UI_NAMES[$i]}" "${REC_UI_PROCESSES[$i]}" "${REC_UI_START[$i]}"
done
echo "default index: ${REC_UI_DEFAULT_INDEX}"

hr "UI BINARIES"
for cmd in kodi kodi-standalone kodi-gbm emulationstation startx startx-rpd labwc labwc-pi wayfire; do
    p="$(rec_which "$cmd" 2>/dev/null)"
    if [[ -z "$p" ]]; then
        # Look outside PATH before declaring it absent - RetroPie lives in /opt.
        p="$(find /opt /usr/local -maxdepth 4 -name "$cmd" -type f 2>/dev/null | head -1)"
        [[ -n "$p" ]] && p="$p  (NOT on PATH)"
    fi
    printf '  %-18s %s\n' "$cmd" "${p:-not found}"
done
echo
echo "kodi packages installed:"
dpkg -l 2>/dev/null | awk '/^ii +kodi/{print "  " $2 " " $3}'

hr "RUNNING PROCESSES"
ps -A -o comm= | grep -iE 'kodi|emulation|xorg|labwc|wayfire' | sort -u | sed 's/^/  /' || echo "  none"
echo "watchdog: $(pgrep -af ui_rotate.sh || echo 'not running')"

hr "AUTOSTART LOG (last 40 lines)"
LOG="$HOME/.local/state/rec/autostart.log"
if [[ -f "$LOG" ]]; then
    tail -40 "$LOG"
else
    echo "  $LOG does not exist - autostart has never run"
fi

if [[ $TRY -eq 1 ]]; then
    idx="${REC_UI_DEFAULT_INDEX:-0}"
    cmd="${REC_UI_START[$idx]%% *}"
    hr "TRYING TO START ${REC_UI_NAMES[$idx]} ($cmd)"
    if [[ "$(tty 2>/dev/null)" != "/dev/tty1" ]]; then
        echo "  NOTE: not on /dev/tty1 - a console UI will fail here for that"
        echo "  reason alone. Re-run this on the physical console for a real test."
    fi
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "  '$cmd' is not installed - that alone explains the failure."
    else
        echo "  running '$cmd' for 15 seconds, capturing output..."
        timeout 15 "$cmd" 2>&1 | tail -30 | sed 's/^/  | /'
        echo "  exit status: ${PIPESTATUS[0]}"
    fi
fi

hr "END OF REPORT"
