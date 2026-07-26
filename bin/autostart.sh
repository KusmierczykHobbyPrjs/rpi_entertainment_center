#!/bin/bash
# ---------------------------------------------------------------------------
# autostart.sh - start every background service this project needs.
#
# Launched once at boot from ~/.bashrc, which the Pi executes because
# raspi-config is set to "Console Autologin". Console autologin (rather than
# desktop autologin) is what lets this script decide which UI comes up.
#
# Each service below guards itself against double-starting, so running this
# script twice is harmless.
#
# To disable a service, comment out its line - or better, leave it here and
# skip that module at install time.
#
# See docs/50-ui-rotation.md and docs/ARCHITECTURE.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

# .bashrc runs for every interactive shell, including each SSH login. Starting
# the UI watchdog from an SSH session would fight with the console session for
# the framebuffer, so only the physical console is allowed to autostart.
# Set REC_FORCE_AUTOSTART=1 to override (useful when testing over SSH).
if [[ "${REC_FORCE_AUTOSTART:-0}" != "1" ]]; then
    case "$(tty)" in
        /dev/tty1) ;;   # physical console - proceed
        *)
            exit 0
            ;;
    esac
fi

rec_log "Starting background services from $REC_ROOT"

# UI watchdog: keeps exactly one of Kodi / RetroPie / Desktop running.
bash "$REC_BIN/ui_rotate.sh" &

# NordVPN: log in, enable meshnet and connect to the first configured country.
bash "$REC_BIN/nordvpn_autostart.sh" &

# NordVPN: announce connection changes out loud.
bash "$REC_BIN/nordvpn_monitor.sh" &

# socat forwarders that expose LAN devices through this Pi.
bash "$REC_BIN/port_forwarding.sh" &

# Physical GPIO buttons.
bash "$REC_BIN/gpio_buttons.sh" &

wait
