#!/bin/bash
# ---------------------------------------------------------------------------
# bluetooth_keepalive.sh - keep the Pi visible as a Bluetooth speaker.
#
# An appliance should not need an SSH session to become findable again. This
# re-asserts the three properties that make pairing possible, and restarts the
# pairing agent if it has died.
#
# Run periodically by bluetooth-keepalive.timer (every 5 minutes). It logs only
# when it had to change something, so the journal stays quiet while all is
# well - and tells you the date a fault started when it is not.
#
# Things that legitimately knock these down:
#   - bluetoothd restarting for any reason (discoverable resets)
#   - bt-agent exceeding its systemd start limit and being given up on
#   - rfkill soft-blocking the adapter
#   - the Pi 3B's combined Wi-Fi/Bluetooth chip resetting after a brownout
#
# See docs/85-bluetooth.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

rec_has bluetoothctl || exit 0

fixed=0

# rfkill takes precedence over everything else: a soft-blocked adapter cannot
# be powered on at all.
if rec_has rfkill && rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes'; then
    rec_warn "Bluetooth was soft-blocked by rfkill - unblocking."
    rfkill unblock bluetooth 2>/dev/null || sudo rfkill unblock bluetooth 2>/dev/null
    fixed=1
    sleep 2
fi

# The agent is what accepts pairing requests, and its start limit means
# systemd may have given up on it permanently.
if ! systemctl is-active --quiet bt-agent 2>/dev/null; then
    if systemctl list-unit-files bt-agent.service >/dev/null 2>&1; then
        rec_warn "bt-agent is not running - resetting and restarting it."
        # reset-failed is required after a start-limit hit, or the restart is
        # refused outright.
        sudo systemctl reset-failed bt-agent 2>/dev/null
        sudo systemctl start bt-agent 2>/dev/null
        fixed=1
        sleep 2
    fi
fi

state="$(timeout 10 bluetoothctl show 2>/dev/null)"
if [[ -z "$state" ]]; then
    rec_error "No Bluetooth adapter responded. Check: dmesg | grep -i blue"
    exit 1
fi

grep -qi 'Powered: yes' <<<"$state" || {
    rec_warn "Adapter was powered off - powering on."
    timeout 10 bluetoothctl power on >/dev/null 2>&1
    fixed=1
}

grep -qi 'Pairable: yes' <<<"$state" || {
    rec_warn "Adapter was not pairable - enabling."
    timeout 10 bluetoothctl pairable on >/dev/null 2>&1
    fixed=1
}

grep -qi 'Discoverable: yes' <<<"$state" || {
    rec_warn "Adapter was not discoverable - enabling."
    timeout 10 bluetoothctl discoverable on >/dev/null 2>&1
    fixed=1
}

if (( fixed == 1 )); then
    rec_log "Bluetooth availability restored."
else
    # Silent on the happy path - this runs every five minutes.
    exit 0
fi
