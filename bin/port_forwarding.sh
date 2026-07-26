#!/bin/bash
# ---------------------------------------------------------------------------
# port_forwarding.sh - expose LAN devices through this Pi.
#
# Runs one socat listener per entry in $REC_PORT_FORWARDS, forwarding a TCP
# port on the Pi to a host:port elsewhere on the LAN.
#
# The point is reachability: the Pi is on NordVPN Meshnet and can be reached
# from anywhere, while the devices behind it (an old Android phone running an
# IP webcam, a printer, a NAS) cannot. Forwarding through the Pi makes them
# reachable without putting any of them on the public internet.
#
# Started in the background by bin/autostart.sh. Runs forever.
# See docs/75-port-forwarding.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

if ! rec_single_instance port_forwarding; then
    exit 0
fi

if ! rec_has socat; then
    rec_warn "socat is not installed. Run: sudo apt-get install socat"
    exit 0
fi

if [[ ${#REC_PORT_FORWARDS[@]} -eq 0 ]]; then
    rec_log "No forwards configured in REC_PORT_FORWARDS - nothing to do."
    exit 0
fi

# Kill the child socat processes when this script is stopped, otherwise they
# survive and hold the listening ports, so the next start fails silently.
pids=()
cleanup() {
    rec_log "Stopping ${#pids[@]} forwarder(s)."
    kill "${pids[@]}" 2>/dev/null
}
trap cleanup EXIT INT TERM

for entry in "${REC_PORT_FORWARDS[@]}"; do
    # Entry format: LISTEN_PORT:TARGET_HOST:TARGET_PORT
    IFS=':' read -r listen_port target_host target_port <<<"$entry"

    if [[ -z "$listen_port" || -z "$target_host" || -z "$target_port" ]]; then
        rec_warn "Skipping malformed forward '$entry' (want PORT:HOST:PORT)."
        continue
    fi

    rec_log "Forwarding *:$listen_port -> $target_host:$target_port"
    # fork:      handle more than one client at a time
    # reuseaddr: rebind immediately after a restart instead of waiting out
    #            the TIME_WAIT window
    socat "tcp-listen:${listen_port},fork,reuseaddr" \
          "tcp:${target_host}:${target_port}" &
    pids+=("$!")
done

if [[ ${#pids[@]} -eq 0 ]]; then
    rec_warn "No valid forwards were started."
    exit 1
fi

wait
