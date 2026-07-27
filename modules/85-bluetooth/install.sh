#!/bin/bash
# ---------------------------------------------------------------------------
# 85-bluetooth - turn the Pi into a Bluetooth speaker.
#
# A phone, laptop or tablet connects to the Pi and its music comes out of the
# Pi's 3.5 mm jack. The Pi is the A2DP *sink*; the phone is the source.
#
# Handles both audio stacks:
#
#   PipeWire     Bookworm and later. WirePlumber links the incoming Bluetooth
#                stream to the output by itself, so there is no loopback to
#                configure. The only real problem is that PipeWire is a user
#                service and Kodi runs with no login session - solved with
#                `loginctl enable-linger`.
#
#   PulseAudio   Bullseye and earlier. Needs system mode, plus the Bluetooth
#                modules added to system.pa, which default.pa loads but
#                system.pa does not.
#
# See docs/85-bluetooth.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

BT_CONF=/etc/bluetooth/main.conf
AGENT_UNIT=/etc/systemd/system/bt-agent.service
PA_SYSTEM=/etc/pulse/system.pa
PA_UNIT=/etc/systemd/system/pulseaudio.service

# Set key=value inside a named [Section] of an INI file, adding either if
# missing. sed cannot do this safely: it has no notion of which section it is
# in, and bluez ignores keys placed under the wrong heading.
ini_set() {
    local file="$1" section="$2" key="$3" value="$4"
    sudo python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys, pathlib
path, section, key, value = sys.argv[1:5]
p = pathlib.Path(path)
lines = p.read_text().splitlines() if p.exists() else []
out, in_section, done, seen = [], False, False, False
for line in lines:
    t = line.strip()
    if t.startswith("[") and t.endswith("]"):
        if in_section and not done:
            out.append(f"{key} = {value}"); done = True
        in_section = t.lower() == f"[{section}]".lower()
        seen = seen or in_section
    elif in_section and not done:
        bare = t.lstrip("#").strip()
        if bare.split("=")[0].strip().lower() == key.lower():
            out.append(f"{key} = {value}"); done = True; continue
    out.append(line)
if in_section and not done:
    out.append(f"{key} = {value}"); done = True
if not seen:
    out += [f"[{section}]", f"{key} = {value}"]
p.write_text("\n".join(out) + "\n")
PY
}

# --- Which audio stack? ----------------------------------------------------
step "Detecting the audio stack"
AUDIO_STACK="none"
if rec_has pipewire || systemctl --user list-unit-files pipewire.service >/dev/null 2>&1; then
    AUDIO_STACK="pipewire"
    ok "PipeWire (Bookworm and later)"
elif rec_has pulseaudio; then
    AUDIO_STACK="pulseaudio"
    ok "PulseAudio (Bullseye and earlier)"
else
    fail "Neither PipeWire nor PulseAudio found."
    note "Install one first: sudo apt install pipewire pipewire-pulse wireplumber"
    exit 1
fi

# --- Packages --------------------------------------------------------------
step "Installing Bluetooth support"
apt_install bluez bluez-tools || exit 1

if [[ "$AUDIO_STACK" == "pipewire" ]]; then
    # libspa-0.2-bluetooth is the SPA plugin that gives PipeWire its Bluetooth
    # support. Without it a phone pairs and connects but no audio node appears.
    apt_install pipewire pipewire-pulse wireplumber libspa-0.2-bluetooth || exit 1
    apt_install pipewire-audio-client-libraries 2>/dev/null || true
else
    apt_install pulseaudio pulseaudio-module-bluetooth pulseaudio-utils || exit 1
fi

# --- Groups ----------------------------------------------------------------
step "Group membership"
ensure_group bluetooth || true
ensure_group audio || true

# --- Adapter selection -----------------------------------------------------
step "Checking Bluetooth adapters"
mapfile -t adapters < <(rec_bt_adapters)

if (( ${#adapters[@]} == 0 )); then
    # Not fatal. Everything else here - packages, the PipeWire config, the
    # keepalive - is still worth installing, and the adapter may simply not be
    # plugged in yet.
    fail "No Bluetooth adapter found."
    note "If you have just plugged in a dongle: dmesg | tail -20"
    note "Continuing; re-run this module once an adapter is present."
fi

have_usb=0; have_builtin=0
for a in "${adapters[@]}"; do
    read -r dev kind mac <<<"$a"
    case "$kind" in
        usb)     ok  "$dev  USB dongle      ($mac)"; have_usb=1 ;;
        builtin) note "$dev  built-in radio  ($mac)"; have_builtin=1 ;;
    esac
done

if (( have_usb == 1 && have_builtin == 1 )); then
    cat <<EOF

  Both a USB dongle and the Pi's built-in radio are present.

  The built-in radio shares one chip and one antenna with 2.4 GHz Wi-Fi, and
  talks over an on-board UART. That is why sustained A2DP on it drops out and
  can wedge the controller entirely. A dongle has neither problem.

  Disabling the built-in radio means:
    - the dongle becomes hci0, so everything targets it with no configuration
    - the UART is freed
    - Bluetooth stops competing with Wi-Fi for the antenna

  This edits /boot/firmware/config.txt and needs a reboot.

EOF
    if confirm "Disable the built-in Bluetooth and use the dongle only?"; then
        BOOTCFG=/boot/firmware/config.txt
        [[ -f "$BOOTCFG" ]] || BOOTCFG=/boot/config.txt
        backup_file "$BOOTCFG"
        if grep -qE '^\s*dtoverlay=disable-bt' "$BOOTCFG"; then
            skip "disable-bt is already set"
        else
            echo "
# Added by rpi-entertainment-center (module 85-bluetooth).
# Disables the Pi's built-in Bluetooth so the USB dongle is the only adapter.
# The built-in radio shares an antenna with Wi-Fi and an on-board UART, which
# makes sustained A2DP unreliable.
dtoverlay=disable-bt" | sudo tee -a "$BOOTCFG" >/dev/null
            ok "Added dtoverlay=disable-bt to $BOOTCFG"
        fi
        # hciuart attaches the built-in radio to the UART; pointless once the
        # overlay disables it, and it fails noisily at boot if left enabled.
        sudo systemctl disable hciuart >/dev/null 2>&1 \
            && ok "Disabled hciuart.service" \
            || skip "hciuart.service not present"
        REC_BT_REBOOT=1
        note "Takes effect after a reboot."
    else
        skip "Keeping both adapters"
        note "bluez uses the first controller; with two present that may be"
        note "the built-in one. Select explicitly with: bluetoothctl select <MAC>"
    fi
elif (( have_usb == 1 )); then
    ok "USB dongle only - the best configuration for audio"
elif (( have_builtin == 1 )); then
    ok "Built-in radio - nothing to configure"
    # Said once, as information rather than a warning: this is the default
    # configuration and it works. It is only sustained A2DP that strains it.
    note "If music later drops out, a USB dongle avoids the antenna shared"
    note "with Wi-Fi. See docs/85-bluetooth.md."
fi

# --- Advertise as a speaker ------------------------------------------------
# This part is identical on both stacks: it is bluez, not the audio system.
step "Advertising the Pi as an audio device"
backup_file "$BT_CONF"

# Class 0x200414 = Audio/Video major class, "portable audio" minor, with the
# audio service bit set. Phones decide whether to offer "connect for media
# audio" from this; left as the default computer class, many will not.
ini_set "$BT_CONF" General Class 0x200414
ini_set "$BT_CONF" General DiscoverableTimeout 0
ini_set "$BT_CONF" General PairableTimeout 0
ini_set "$BT_CONF" General AlwaysPairable true
ini_set "$BT_CONF" Policy AutoEnable true
ok "Class 0x200414, discoverable and pairable with no timeout"

# Default to whatever is currently advertised, not the hostname - otherwise
# re-running the module shows "[raspberrypi]" and looks as though the name you
# chose last time did not stick.
default_name="$(timeout 5 bluetoothctl show 2>/dev/null | grep -oP '^\s*Alias:\s*\K.*' | head -1)"
[[ -n "$default_name" ]] || default_name="$(hostnamectl --pretty 2>/dev/null)"
[[ -n "$default_name" ]] || default_name="$(grep -oP '^\s*Name\s*=\s*\K.*' "$BT_CONF" 2>/dev/null | head -1)"
[[ -n "$default_name" ]] || default_name="$(hostname)"
if [[ "${REC_ASSUME_YES:-0}" == "1" ]]; then
    bt_name="$default_name"
else
    read -r -p "  Name to show on phones [$default_name]: " bt_name
    bt_name="${bt_name:-$default_name}"
fi
# Belt and braces, because which mechanism applies varies by bluez version:
#   main.conf [General] Name   works on current Raspberry Pi OS
#   pretty hostname            what newer bluez derives the name from
#   bluetoothctl system-alias  applies immediately, no restart needed
ini_set "$BT_CONF" General Name "$bt_name"
if sudo timeout 10 hostnamectl set-hostname --pretty "$bt_name" 2>/dev/null; then
    ok "Pretty hostname set to '$bt_name' (this is what phones show)"
else
    skip "Could not set the pretty hostname"
fi
# Belt and braces: set the adapter alias directly too. Harmless if the pretty
# hostname already covers it.
sudo timeout 10 bluetoothctl system-alias "$bt_name" >/dev/null 2>&1 \
    && ok "Adapter alias set to '$bt_name'" \
    || skip "Could not set the adapter alias (bluetoothctl unavailable?)"

sudo systemctl enable --now bluetooth >/dev/null 2>&1
# Bound this: a bluetoothd that will not stop would otherwise hang the whole
# installer with no indication of why.
if sudo timeout 30 systemctl restart bluetooth; then
    ok "bluetooth.service restarted with the new settings"
else
    fail "bluetooth.service did not restart within 30s."
    note "The settings are written; they will apply after a reboot."
    note "If shutdown is also slow, check: systemctl list-jobs"
fi

# --- Pairing agent ---------------------------------------------------------
step "Installing the pairing agent"
# There is no keyboard on the Pi to confirm a PIN, so an agent with
# NoInputNoOutput capability accepts "just works" pairing.
sudo tee "$AGENT_UNIT" >/dev/null <<'EOF'
[Unit]
Description=Bluetooth pairing agent (accepts pairing without a keyboard)
After=bluetooth.service
Requires=bluetooth.service
# StartLimit* belong in [Unit]. Placed in [Service] systemd ignores them with
# "Unknown key ... in section [Service]" and the limit silently does nothing.
StartLimitIntervalSec=120
StartLimitBurst=5

[Service]
Type=simple
# StandardInput=null is load-bearing. bluetoothctl reads stdin, and under
# systemd there is no terminal - given a tty it would sit waiting for input
# forever, so the unit never finishes starting and systemd then waits out the
# full stop timeout at shutdown. `timeout` and the leading `-` make sure a
# misbehaving helper can never block the unit either way.
StandardInput=null
ExecStartPost=-/usr/bin/timeout 5 /usr/bin/bluetoothctl discoverable on
ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput
Restart=always
RestartSec=5
TimeoutStartSec=15

# bt-agent does not exit on SIGTERM. Left to systemd's defaults that means
# every shutdown stalls for the full 90-second stop timeout on
# "Job bt-agent.service/stop running".
#
# It is a D-Bus agent with no state to flush - bluez drops the registration
# when the connection closes - so there is nothing to lose by killing it
# outright. SIGKILL makes shutdown immediate; TimeoutStopSec is a backstop.
KillSignal=SIGKILL
KillMode=mixed
TimeoutStopSec=5
SendSIGKILL=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload

# An earlier version of this unit had no stop bound, and bt-agent ignores
# SIGTERM - so a machine that ran it stalls ~90s on every shutdown until the
# new unit is in place. Stop the old one first so the fix applies now rather
# than after one more slow reboot.
sudo timeout 20 systemctl stop bt-agent >/dev/null 2>&1
sudo systemctl reset-failed bt-agent >/dev/null 2>&1

if sudo timeout 30 systemctl enable --now bt-agent >/dev/null 2>&1; then
    systemctl is-active --quiet bt-agent \
        && ok "bt-agent is running - the Pi accepts pairing requests" \
        || fail "bt-agent enabled but not active. Check: sudo journalctl -u bt-agent -n 30"
else
    fail "bt-agent did not start within 30s - disabling it again so it cannot"
    fail "delay shutdown."
    sudo timeout 20 systemctl disable --now bt-agent >/dev/null 2>&1
    sudo systemctl reset-failed bt-agent >/dev/null 2>&1
    note "Check: sudo journalctl -u bt-agent -n 30"
fi

# --- Keepalive -------------------------------------------------------------
step "Installing the availability keepalive"
# Discoverability is not permanent in practice. bluetoothd restarting resets
# it, rfkill can soft-block the adapter, the Pi 3B's combined Wi-Fi/Bluetooth
# chip resets after a brownout, and bt-agent can exceed its systemd start
# limit and be given up on for good - after which the Pi silently disappears
# from every phone's device list and never returns on its own.
#
# A five-minute timer re-asserts powered/pairable/discoverable and revives the
# agent. It logs only when it had to change something.
sudo tee /etc/systemd/system/bluetooth-keepalive.service >/dev/null <<EOF
[Unit]
Description=Keep the Pi discoverable as a Bluetooth speaker
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
User=$USER
StandardInput=null
TimeoutStartSec=60
ExecStart=$REC_BIN/bluetooth_keepalive.sh
EOF

sudo tee /etc/systemd/system/bluetooth-keepalive.timer >/dev/null <<'EOF'
[Unit]
Description=Re-assert Bluetooth availability every 5 minutes

[Timer]
# Soon after boot, then steadily. Persistent=false: a missed run while powered
# off is meaningless, and catching up on boot would only duplicate the first.
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
if sudo timeout 20 systemctl enable --now bluetooth-keepalive.timer >/dev/null 2>&1; then
    ok "Keepalive timer enabled (runs every 5 minutes)"
    note "It logs only when it fixes something: journalctl -u bluetooth-keepalive"
else
    fail "Could not enable the keepalive timer"
fi

# --- Keep audio alive without a login session ------------------------------
if [[ "$AUDIO_STACK" == "pipewire" ]]; then
    step "Making PipeWire run without a login session"
    cat <<EOF

  PipeWire and WirePlumber are per-user services, started when you log in.
  Kodi and EmulationStation run from a console with no graphical session, so
  without this the speaker works on the desktop and goes silent everywhere
  else.

  Lingering keeps your user's systemd instance - and therefore PipeWire -
  running from boot, whether or not anyone is logged in. This is the modern
  replacement for PulseAudio's system mode, and is far less invasive.

EOF
    if confirm "Enable lingering for $USER? (recommended)"; then
        if sudo loginctl enable-linger "$USER"; then
            ok "Lingering enabled - PipeWire will run from boot"
        else
            fail "Could not enable lingering"
        fi
    else
        skip "Left disabled - Bluetooth audio will only work in a desktop session"
    fi

    step "Enabling the PipeWire services"
    systemctl --user enable --now pipewire.socket pipewire.service \
        wireplumber.service pipewire-pulse.socket 2>/dev/null \
        && ok "PipeWire and WirePlumber enabled" \
        || skip "Could not enable them from here (normal over SSH with no session)"

    step "Configuring the Bluetooth audio role"
    # WirePlumber already enables the a2dp_sink role by default, so this is
    # only about quality: SBC-XQ is a higher-bitrate SBC variant that every
    # A2DP source supports, and is a clear improvement over baseline SBC.
    WP_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
    mkdir -p "$WP_DIR"
    cat > "$WP_DIR/51-rec-bluetooth.conf" <<'EOF'
# Installed by rpi-entertainment-center (module 85-bluetooth).
#
# a2dp_sink is what lets this machine RECEIVE audio from a phone. It is on by
# default; listed explicitly so the intent is visible.
#
# SBC-XQ is a higher-bitrate SBC profile and does sound better - but it needs
# more airtime, and a Pi 3B shares one antenna between Bluetooth and 2.4 GHz
# Wi-Fi. On a marginal link the extra bandwidth buys audible dropouts rather
# than audible quality, so it is OFF by default here.
#
# Turn it on only once playback is reliably stable, and be ready to turn it
# back off:
#   bluez5.enable-sbc-xq = true
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source ]
  bluez5.enable-sbc-xq = false
}
EOF
    ok "Wrote $WP_DIR/51-rec-bluetooth.conf (SBC-XQ off - stability first)"
    systemctl --user restart wireplumber 2>/dev/null || true
else
    # --- PulseAudio (Bullseye) --------------------------------------------
    step "PulseAudio system mode"
    cat <<EOF

  Bluetooth audio is routed through PulseAudio, which normally runs once per
  login session. Kodi and the console have none, so the speaker would work on
  the desktop only.

  System mode runs one PulseAudio for the whole machine. Upstream discourages
  it, but it is the standard answer for an appliance.

EOF
    if confirm "Enable system-mode PulseAudio?"; then
        backup_file "$PA_SYSTEM"
        # system.pa does NOT load the Bluetooth modules that default.pa does.
        # Without them a phone pairs and connects and no sound ever arrives.
        if grep -q "module-bluetooth-discover" "$PA_SYSTEM" 2>/dev/null; then
            skip "system.pa already loads the Bluetooth modules"
        else
            sudo tee -a "$PA_SYSTEM" >/dev/null <<'EOF'

### Added by rpi-entertainment-center (module 85-bluetooth)
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
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=notify
ExecStart=pulseaudio --daemonize=no --system --realtime --log-target=journal
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        for grp in bluetooth audio; do
            id -nG pulse 2>/dev/null | grep -qw "$grp" || sudo usermod -a -G "$grp" pulse 2>/dev/null
        done
        sudo systemctl daemon-reload
        sudo systemctl enable --now pulseaudio \
            && ok "System-mode PulseAudio enabled" \
            || fail "It did not start. Check: sudo journalctl -u pulseaudio -n 30"
    else
        skip "Left in per-user mode - desktop only"
    fi
fi

# --- Output to the jack ----------------------------------------------------
step "Routing audio to the 3.5 mm jack"
if rec_has raspi-config; then
    sudo raspi-config nonint do_audio 1 \
        && ok "Analogue jack selected" \
        || skip "Set it by hand: raspi-config -> System Options -> Audio"
fi

if [[ "$AUDIO_STACK" == "pipewire" ]] && rec_has wpctl; then
    analog="$(wpctl status 2>/dev/null | grep -i 'analog' | grep -oE '^\s*[│├└─ ]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
    if [[ -n "$analog" ]]; then
        wpctl set-default "$analog" 2>/dev/null \
            && ok "Default output set to the analogue jack" \
            || skip "Could not set the default sink"
    else
        skip "No analogue sink visible from here (normal over SSH)"
    fi
fi

echo
ok "Bluetooth speaker configured."
cat <<EOF

${REC_C_BOLD}Connect a phone${REC_C_OFF}

  1. Phone > Settings > Bluetooth
  2. Pick "${bt_name}" and pair - there is no PIN
  3. Play something; sound comes out of the Pi's 3.5 mm jack

  The Pi stays discoverable, so it appears without anything being pressed.

${REC_C_BOLD}Check it${REC_C_OFF}

    $REC_BIN/doctor.sh bluetooth
    wpctl status                    # the phone appears once connected
    bluetoothctl devices

${REC_C_BOLD}If it is quiet${REC_C_OFF}

    wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%

  Set volume with wpctl, never amixer - WirePlumber overwrites ALSA at every
  boot. See docs/TROUBLESHOOTING.md.

Full walkthrough: docs/85-bluetooth.md
EOF

if [[ "${REC_BT_REBOOT:-0}" == "1" ]]; then
    echo
    fail "REBOOT REQUIRED - the built-in radio is disabled from the next boot."
    note "Until then both adapters are present and bluez may target the wrong one."
fi
