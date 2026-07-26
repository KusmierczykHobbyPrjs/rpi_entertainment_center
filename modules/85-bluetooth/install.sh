#!/bin/bash
# ---------------------------------------------------------------------------
# 85-bluetooth - turn the Pi into a Bluetooth speaker.
#
# A phone, laptop or tablet connects to the Pi and its music comes out of the
# Pi's 3.5 mm jack, into whatever hi-fi or powered speakers are plugged in.
# The Pi is the A2DP *sink*; the phone is the source.
#
# Three things have to be true, and most tutorials only cover the first:
#
#   1. bluez must advertise the Pi as an audio device, stay discoverable, and
#      accept pairing from a device with no keyboard attached
#   2. PulseAudio must bridge the incoming Bluetooth stream to the jack
#   3. that has to keep working under Kodi and the console, which have no
#      login session and therefore no per-user PulseAudio
#
# See docs/85-bluetooth.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

BT_CONF=/etc/bluetooth/main.conf
PA_SYSTEM=/etc/pulse/system.pa
PA_UNIT=/etc/systemd/system/pulseaudio.service
AGENT_UNIT=/etc/systemd/system/bt-agent.service

# Set key=value inside a named [Section] of an INI file, adding either if
# missing. sed alone cannot do this safely: it has no notion of which section
# it is in, and bluez ignores keys placed under the wrong heading.
ini_set() {
    local file="$1" section="$2" key="$3" value="$4"
    sudo python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys, pathlib
path, section, key, value = sys.argv[1:5]
p = pathlib.Path(path)
lines = p.read_text().splitlines() if p.exists() else []

out, in_section, done, seen_section = [], False, False, False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_section and not done:      # leaving our section: write it here
            out.append(f"{key} = {value}")
            done = True
        in_section = stripped.lower() == f"[{section}]".lower()
        seen_section = seen_section or in_section
    elif in_section and not done:
        bare = stripped.lstrip("#").strip()   # replace commented-out keys too
        if bare.split("=")[0].strip().lower() == key.lower():
            out.append(f"{key} = {value}")
            done = True
            continue
    out.append(line)

if in_section and not done:
    out.append(f"{key} = {value}")
    done = True
if not seen_section:
    out += [f"[{section}]", f"{key} = {value}"]

p.write_text("\n".join(out) + "\n")
PY
}

# --- Packages --------------------------------------------------------------
step "Installing Bluetooth and audio packages"
apt_install bluez pulseaudio pulseaudio-module-bluetooth pulseaudio-utils || exit 1

step "Installing the pairing agent"
# Without an agent the Pi cannot complete a pairing at all - there is no
# keyboard on it to confirm anything with.
apt_install bluez-tools || exit 1

# --- Groups ----------------------------------------------------------------
step "Adding $USER to the audio groups"
for grp in bluetooth audio pulse-access; do
    if getent group "$grp" >/dev/null 2>&1; then
        if id -nG "$USER" | grep -qw "$grp"; then
            skip "$USER is already in '$grp'"
        else
            sudo usermod -a -G "$grp" "$USER"
            ok "Added $USER to '$grp' (takes effect after the next login)"
        fi
    fi
done

# --- Advertise as a speaker ------------------------------------------------
step "Advertising the Pi as an audio device"
backup_file "$BT_CONF"

# Class 0x200414 = Audio/Video major class, "portable audio" minor, audio
# service bit set. Phones decide whether to offer "connect for media audio"
# from this; left as the default computer class many simply will not.
ini_set "$BT_CONF" General Class 0x200414
ok "Device class set to 0x200414 (portable audio)"

# 0 means no timeout: stay discoverable and pairable indefinitely, which is
# what an appliance with no screen needs.
ini_set "$BT_CONF" General DiscoverableTimeout 0
ini_set "$BT_CONF" General PairableTimeout 0
ini_set "$BT_CONF" General AlwaysPairable true
ini_set "$BT_CONF" Policy AutoEnable true
ok "Discoverable and pairable with no timeout"

default_name="$(hostname)"
if [[ "${REC_ASSUME_YES:-0}" == "1" ]]; then
    bt_name="$default_name"
else
    read -r -p "  Name to show on phones [$default_name]: " bt_name
    bt_name="${bt_name:-$default_name}"
fi
ini_set "$BT_CONF" General Name "$bt_name"
ok "Advertised name: $bt_name"

sudo systemctl enable --now bluetooth >/dev/null 2>&1
sudo systemctl restart bluetooth
ok "bluetooth.service restarted with the new settings"

# --- Pairing agent ---------------------------------------------------------
step "Installing the pairing agent service"
# NoInputNoOutput means "just works" pairing - no PIN on a device with no
# keyboard. Anyone in Bluetooth range can pair while it is discoverable, which
# is the trade-off an appliance speaker makes. See docs/85-bluetooth.md.
sudo tee "$AGENT_UNIT" >/dev/null <<'EOF'
[Unit]
Description=Bluetooth pairing agent (accepts pairing without a keyboard)
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/bluetoothctl discoverable on
ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now bt-agent >/dev/null 2>&1
if systemctl is-active --quiet bt-agent; then
    ok "bt-agent is running - the Pi will accept pairing requests"
else
    fail "bt-agent did not start. Check: sudo journalctl -u bt-agent -n 30"
fi

# --- Output to the jack ----------------------------------------------------
step "Routing audio to the 3.5 mm jack"
if rec_has raspi-config; then
    # do_audio: 0 = auto, 1 = headphones/jack, 2 = HDMI
    if sudo raspi-config nonint do_audio 1; then
        ok "Analogue jack selected as the output"
    else
        skip "Could not set it automatically"
        note "sudo raspi-config -> System Options -> Audio -> Headphones"
    fi
else
    skip "raspi-config not found - select the jack output by hand"
fi

# --- PulseAudio ------------------------------------------------------------
step "Bridging Bluetooth through to the jack"
cat <<EOF

  When a phone connects, PulseAudio sees the incoming stream as a *source*
  and has to loop it through to the jack. module-bluetooth-policy does that
  automatically - but only if it is loaded.

  Per-user PulseAudio loads it from /etc/pulse/default.pa, so this works on
  the desktop out of the box. Kodi and the console have no login session and
  so no PulseAudio at all, and the music stops when you leave the desktop.

  System mode runs one PulseAudio for the whole machine, started at boot.
  The trade-off is that upstream discourages it and all users share one
  audio session.

  Say no if you only use the Pi as a speaker while the desktop is up.

EOF
if confirm "Enable system-mode PulseAudio (recommended for this use case)?"; then
    backup_file "$PA_SYSTEM"

    # The bit almost every guide misses: /etc/pulse/system.pa does NOT load
    # the Bluetooth modules, unlike default.pa. Switching to system mode
    # without adding them leaves a phone able to pair and connect while no
    # sound ever reaches the jack.
    if grep -q "module-bluetooth-discover" "$PA_SYSTEM" 2>/dev/null; then
        skip "system.pa already loads the Bluetooth modules"
    else
        sudo tee -a "$PA_SYSTEM" >/dev/null <<'EOF'

### Added by rpi-entertainment-center (module 85-bluetooth)
### system.pa does not load these by default, unlike default.pa. Without them
### a phone can pair and connect but no sound ever reaches the jack.
.ifexists module-bluetooth-discover.so
load-module module-bluetooth-discover
.endif
.ifexists module-bluetooth-policy.so
load-module module-bluetooth-policy
.endif
EOF
        ok "Added the Bluetooth modules to $PA_SYSTEM"
    fi

    sudo tee "$PA_UNIT" >/dev/null <<'EOF'
[Unit]
Description=PulseAudio system server
Documentation=man:pulseaudio(1)
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=notify
ExecStart=pulseaudio --daemonize=no --system --realtime --log-target=journal
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    ok "Wrote $PA_UNIT"

    # In system mode the daemon runs as the 'pulse' user, which needs to reach
    # bluez over D-Bus and to open the sound card.
    for grp in bluetooth audio; do
        if getent group "$grp" >/dev/null 2>&1 && ! id -nG pulse 2>/dev/null | grep -qw "$grp"; then
            sudo usermod -a -G "$grp" pulse 2>/dev/null \
                && ok "Added the 'pulse' user to '$grp'"
        fi
    done

    # A per-user daemon holding the card would fight the system one.
    if pgrep -u "$USER" pulseaudio >/dev/null 2>&1; then
        note "Stopping the per-user PulseAudio first"
        systemctl --user stop pulseaudio.socket pulseaudio.service 2>/dev/null
        pulseaudio --kill 2>/dev/null
        sleep 1
    fi

    sudo systemctl daemon-reload
    if sudo systemctl enable --now pulseaudio; then
        ok "System-mode PulseAudio enabled"
    else
        fail "It did not start. Check: sudo journalctl -u pulseaudio -n 30"
    fi
else
    skip "Left PulseAudio in per-user mode"
    note "The Pi will work as a speaker on the desktop, but not under Kodi."
fi

echo
ok "Bluetooth speaker configured."
cat <<EOF

${REC_C_BOLD}Connect a phone${REC_C_OFF}

  1. Phone > Settings > Bluetooth
  2. Pick "${bt_name}" from the list and pair - there is no PIN to enter
  3. Play something; the sound comes out of the Pi's 3.5 mm jack

  The Pi stays discoverable, so it appears without anything being pressed
  on it.

${REC_C_BOLD}Check it is working${REC_C_OFF}

    $REC_BIN/doctor.sh bluetooth
    pactl list sources short | grep bluez     # the phone, once connected
    pactl list sinks short                    # the jack

${REC_C_BOLD}If there is no sound${REC_C_OFF}

  Confirm the jack is the default output, and turn it up:

    pactl set-default-sink \$(pactl list sinks short | awk '/analog/{print \$2; exit}')
    alsamixer

Full walkthrough and troubleshooting: docs/85-bluetooth.md
EOF
