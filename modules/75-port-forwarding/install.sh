#!/bin/bash
# ---------------------------------------------------------------------------
# 75-port-forwarding - make LAN devices reachable through the Pi.
#
# The Pi is on Meshnet and therefore reachable from anywhere. The devices
# around it usually are not: an old Android phone running an IP webcam cannot
# run a VPN client, and putting it on the public internet is exactly what you
# do not want.
#
# socat listens on a port on the Pi and relays to the device, so
# meshnet-address:8282 becomes the webcam without the webcam being exposed to
# anyone else.
#
# See docs/75-port-forwarding.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"
rec_load_config

require_not_root

step "Installing socat"
apt_install socat || exit 1

step "Checking the configured forwards"
if [[ ${#REC_PORT_FORWARDS[@]} -eq 0 ]]; then
    skip "No forwards configured in REC_PORT_FORWARDS"
    note "Add entries to config.sh in the form PORT:HOST:PORT, e.g."
    note '  declare -a REC_PORT_FORWARDS=("8282:192.168.1.20:8080")'
    exit 0
fi

problems=0
for entry in "${REC_PORT_FORWARDS[@]}"; do
    IFS=':' read -r listen_port target_host target_port <<<"$entry"

    if [[ -z "$listen_port" || -z "$target_host" || -z "$target_port" ]]; then
        fail "Malformed entry (want PORT:HOST:PORT): $entry"
        problems=$((problems + 1))
        continue
    fi

    ok "*:$listen_port -> $target_host:$target_port"

    # Warn about a port that something else already owns; socat would start,
    # fail to bind, and the forward would silently not exist.
    if ss -tlnH "sport = :$listen_port" 2>/dev/null | grep -q .; then
        fail "  Port $listen_port is already in use by another process:"
        ss -tlnp "sport = :$listen_port" 2>/dev/null | sed 's/^/    /'
        problems=$((problems + 1))
    fi

    # Check the target is actually reachable right now. Not fatal (the device
    # may be asleep), but it catches typos in the IP immediately.
    if rec_has nc; then
        if nc -z -w2 "$target_host" "$target_port" 2>/dev/null; then
            ok "  Target $target_host:$target_port responds"
        else
            skip "  Target $target_host:$target_port did not respond (device off?)"
        fi
    fi
done

step "Opening the firewall"
if rec_has ufw && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    for entry in "${REC_PORT_FORWARDS[@]}"; do
        IFS=':' read -r listen_port _ _ <<<"$entry"
        [[ -n "$listen_port" ]] || continue
        sudo ufw allow "$listen_port/tcp" comment "rec port forward" >/dev/null
        ok "Allowed $listen_port/tcp through ufw"
    done
else
    skip "ufw is not active - nothing to open"
fi

echo
if (( problems > 0 )); then
    fail "$problems problem(s) found above - fix config.sh and re-run."
else
    ok "Port forwarding configured."
fi

cat <<EOF

${REC_C_BOLD}How to use it${REC_C_OFF}

The forwards start automatically at boot via autostart.sh. Start them now
without rebooting:

    bash $REC_BIN/port_forwarding.sh &

Then reach the device through the Pi:

  - on the LAN:      http://$(hostname -I | awk '{print $1}'):<port>
  - from anywhere:   http://<pi-meshnet-address>:<port>
                     (find it with: nordvpn meshnet peer list)

${REC_C_BOLD}Security note${REC_C_OFF}

These forwards have no authentication of their own - anything that can reach
the port reaches the device. That is safe over Meshnet, which is private to
your account. Do not forward the same ports on your router unless the device
behind them has its own password.
EOF
