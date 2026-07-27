#!/bin/bash
# ---------------------------------------------------------------------------
# doctor.sh - check that everything is installed and configured correctly.
#
# Run this after installing, after changing config.sh, and first thing when
# something stops working. It only reads state - it changes nothing.
#
#   doctor.sh              check everything
#   doctor.sh vpn          check one section
#                          (base|autostart|kodi|ui|gpio|vpn|net|web|audio|
#                           bluetooth|weather)
#
# Every failure line says what to do about it.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

if [[ -t 1 ]]; then
    C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_OFF=""
fi

PASS=0; WARN=0; FAIL=0

section() { printf '\n%s%s%s\n%s\n' "$C_BOLD" "$1" "$C_OFF" "$(printf '%.0s-' {1..60})"; }
pass()    { printf '  %sPASS%s  %s\n' "$C_GREEN"  "$C_OFF" "$1"; PASS=$((PASS+1)); }
warn()    { printf '  %sWARN%s  %s\n' "$C_YELLOW" "$C_OFF" "$1"; WARN=$((WARN+1));
            [[ -n "${2:-}" ]] && printf '        -> %s\n' "$2"; }
bad()     { printf '  %sFAIL%s  %s\n' "$C_RED"    "$C_OFF" "$1"; FAIL=$((FAIL+1));
            [[ -n "${2:-}" ]] && printf '        -> %s\n' "$2"; }

want="${1:-all}"
run_section() { [[ "$want" == "all" || "$want" == "$1" ]]; }

# Redact a secret down to its length, so the health check can confirm a value
# is present without printing it into a log the user may paste somewhere.
masked() { local v="$1"; [[ -n "$v" ]] && echo "set (${#v} chars)" || echo "empty"; }

# ===========================================================================
if run_section base; then
section "Base"

if [[ -f "$REC_ROOT/config.sh" ]]; then
    pass "config.sh exists"
    perms="$(stat -c '%a' "$REC_ROOT/config.sh")"
    if [[ "$perms" == "600" ]]; then
        pass "config.sh permissions are 600"
    else
        warn "config.sh permissions are $perms (it holds your VPN token)" \
             "chmod 600 $REC_ROOT/config.sh"
    fi
else
    bad "config.sh is missing" "cp $REC_ROOT/config.example.sh $REC_ROOT/config.sh"
fi

if grep -q "rpi-entertainment-center" "$HOME/.bashrc" 2>/dev/null; then
    pass "autostart.sh is hooked into ~/.bashrc"
else
    bad "autostart.sh is not started at login" "./install.sh 00-base"
fi

boot_target="$(systemctl get-default 2>/dev/null)"
if [[ "$boot_target" == "multi-user.target" ]]; then
    pass "Boots to console (multi-user.target)"
else
    bad "Boots to $boot_target, not the console" \
        "sudo raspi-config -> System Options -> Boot/Auto Login -> Console Autologin"
fi

if [[ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]]; then
    pass "Console autologin is configured"
else
    bad "Console autologin is not configured" \
        "sudo raspi-config nonint do_boot_behaviour B2"
fi

# Non-executable scripts are a common result of copying the repo over a
# filesystem that drops the permission bits (FAT USB stick, some zips).
nonexec=0
for f in "$REC_BIN"/*.sh "$REC_BIN"/*.py; do
    [[ -f "$f" ]] || continue
    [[ -x "$f" ]] || nonexec=$((nonexec+1))
done
if (( nonexec == 0 )); then
    pass "All scripts in bin/ are executable"
else
    warn "$nonexec script(s) in bin/ are not executable" \
         "chmod +x $REC_BIN/*.sh $REC_BIN/*.py"
fi
fi

# ===========================================================================
if run_section autostart; then
section "Autostart"

REC_LOG="$HOME/.local/state/rec/autostart.log"

if [[ -f "$REC_LOG" ]]; then
    pass "Autostart log exists: $REC_LOG"

    last_any="$(grep -- '--- autostart invoked' "$REC_LOG" | tail -1 | cut -d' ' -f1-2)"
    [[ -n "$last_any" ]] && note_line="$last_any" || note_line="never"
    pass "Last invoked: $note_line"

    # Search the WHOLE log, not a fixed tail window: every SSH login appends a
    # few lines, so a console run scrolls out of view after a handful of
    # logins and a tail-based check reports a false failure.
    last_console="$(grep -B1 'On the console - proceeding' "$REC_LOG" 2>/dev/null \
                    | grep -- '--- autostart invoked' | tail -1 | cut -d' ' -f1-2)"
    if [[ -z "$last_console" ]]; then
        last_console="$(grep 'On the console - proceeding' "$REC_LOG" | tail -1 | cut -d' ' -f1-2)"
    fi

    if [[ -n "$last_console" ]]; then
        pass "Last ran on the console: $last_console"

        # The question that actually matters: did it run on the console since
        # this machine booted? If not, this boot did not start the services.
        boot_epoch="$(date -d "$(uptime -s)" +%s 2>/dev/null || echo 0)"
        cons_epoch="$(date -d "$last_console" +%s 2>/dev/null || echo 0)"
        if (( cons_epoch >= boot_epoch )); then
            pass "It ran on the console during the current boot"
        else
            bad "It has NOT run on the console since this boot ($(uptime -s))" \
                "The Pi is not reaching a console login. Check: systemctl get-default"
        fi
    else
        bad "Autostart has never run on the console, so nothing was ever started" \
            "The Pi is booting to the desktop. Run: ./install.sh 00-base, then reboot"
    fi

    if grep -q ' SKIP ' "$REC_LOG" 2>/dev/null; then
        warn "Some services were skipped" "grep SKIP $REC_LOG"
    fi
    if grep -qi 'error\|not found\|command not found' "$REC_LOG" 2>/dev/null; then
        warn "The log contains errors" "tail -40 $REC_LOG"
    fi
else
    warn "No autostart log yet ($REC_LOG)" \
         "It is written on the first console boot. Normal before a reboot."
fi

# A display manager beats the console to the screen even with the right
# boot target, and the symptom is identical to autostart never running.
for dm in lightdm gdm3 sddm greetd; do
    if systemctl is-enabled --quiet "$dm" 2>/dev/null; then
        bad "Display manager '$dm' is enabled and will take the screen" \
            "sudo systemctl disable $dm"
    fi
done

# Which display server is actually configured, not merely installed.
case "$(rec_display_server)" in
    wayland) pass "Display server: Wayland (UI start command must be labwc/wayfire)" ;;
    x11)     pass "Display server: X11 (UI start command must be startx)" ;;
    *)
        note_avail=""
        rec_has startx && note_avail="startx"
        rec_has labwc  && note_avail="${note_avail:+$note_avail, }labwc"
        warn "Could not determine the display server (installed: ${note_avail:-none})" \
             "Check from a desktop session: echo \$XDG_SESSION_TYPE"
        ;;
esac
fi

# ===========================================================================
if run_section kodi; then
section "Kodi"

if rec_has kodi; then
    pass "Kodi is installed"
    for pkg in kodi-inputstream-adaptive kodi-eventclients-kodi-send kodi-peripheral-joystick; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            pass "$pkg is installed"
        else
            warn "$pkg is missing" "./install.sh 10-kodi"
        fi
    done

    if dpkg-query -W -f='${Status}' kodi-pvr-iptvsimple 2>/dev/null | grep -q "ok installed"; then
        pass "IPTV client is installed"
        playlists="$(find "$HOME/.local/share/rec-iptv" -name '*.m3u' 2>/dev/null | wc -l)"
        if (( playlists > 0 )); then
            pass "$playlists IPTV playlist(s) installed"
        else
            warn "No IPTV playlists found" "./install.sh 15-kodi-iptv"
        fi
    else
        warn "IPTV client is not installed" "./install.sh 15-kodi-iptv"
    fi

    if [[ -f "$HOME/shell_command_launcher.menu" ]]; then
        pass "Shell Script Launcher menu is installed"
        if grep -q '@REC_BIN@' "$HOME/shell_command_launcher.menu"; then
            bad "Menu still contains the @REC_BIN@ placeholder" "./install.sh 20-kodi-addons"
        fi
    else
        warn "Shell Script Launcher menu is missing" "./install.sh 20-kodi-addons"
    fi
else
    warn "Kodi is not installed" "./install.sh 10-kodi"
fi
fi

# ===========================================================================
if run_section ui; then
section "UI rotation"

n=${#REC_UI_PROCESSES[@]}
if [[ ${#REC_UI_NAMES[@]} -eq $n && ${#REC_UI_START[@]} -eq $n && ${#REC_UI_STOP[@]} -eq $n ]]; then
    pass "The four UI arrays all have $n entries"
else
    bad "The UI arrays in config.sh have different lengths" \
        "REC_UI_PROCESSES/NAMES/START/STOP must all match - see docs/50-ui-rotation.md"
fi

for i in "${!REC_UI_NAMES[@]}"; do
    binary="${REC_UI_START[$i]%% *}"
    if rec_has "$binary"; then
        pass "${REC_UI_NAMES[$i]} -> $(rec_which "$binary")"
    else
        # Do not claim it is missing without looking outside PATH first.
        found="$(find /opt /usr/local -maxdepth 4 -name "$binary" -type f 2>/dev/null | head -1)"
        if [[ -n "$found" ]]; then
            bad "${REC_UI_NAMES[$i]} -> '$binary' is not on PATH, but exists at $found" \
                "Use the absolute path in REC_UI_START in config.sh"
        else
            bad "${REC_UI_NAMES[$i]} -> $binary is not installed" \
                "Install it, or remove index $i from all four arrays in config.sh"
        fi
    fi

    # The two start commands that are commonly wrong rather than missing.
    case "$binary" in
        kodi)
            if rec_has kodi-standalone || rec_has kodi-gbm; then
                bad "REC_UI_START uses plain 'kodi', which needs an X server" \
                    "From a console use kodi-standalone (or kodi-gbm) instead"
            fi
            ;;
        startx|labwc|wayfire)
            # These are the bare compositor / X starter. They come up with no
            # panel and no file manager, which reads as a black screen.
            bad "REC_UI_START uses '$binary', which is not a desktop session" \
                "Use 'labwc-pi &' (Wayland) or 'startx-rpd &' (X11) - see docs/40-desktop.md"
            ;;
        labwc-pi)
            if [[ "$(rec_display_server)" == "x11" ]]; then
                bad "REC_UI_START uses 'labwc-pi' but this session is X11" \
                    "Use 'startx-rpd &' with process name 'Xorg'"
            fi
            ;;
        startx-rpd)
            if [[ "$(rec_display_server)" == "wayland" ]]; then
                bad "REC_UI_START uses 'startx-rpd' but this session is Wayland" \
                    "Use 'labwc-pi &' with process name 'labwc'"
            fi
            ;;
    esac
done

# Kodi from a console reaches the GPU and input devices directly, so it needs
# these groups. They used to be granted only by the RetroPie module.
missing_groups=()
for grp in video render input tty; do
    getent group "$grp" >/dev/null 2>&1 || continue
    id -nG "$USER" | grep -qw "$grp" || missing_groups+=("$grp")
done
if (( ${#missing_groups[@]} == 0 )); then
    pass "$USER is in the groups a console UI needs"
else
    bad "$USER is not in: ${missing_groups[*]}" \
        "Kodi will exit immediately from a console. Run: ./install.sh 10-kodi, then reboot"
fi

# The kernel truncates process names to 15 characters, so a longer entry can
# never be matched exactly - and the force-kill escalation would do nothing.
for i in "${!REC_UI_PROCESSES[@]}"; do
    pname="${REC_UI_PROCESSES[$i]}"
    if (( ${#pname} > 15 )); then
        warn "REC_UI_PROCESSES[$i]='$pname' is ${#pname} chars (limit is 15)" \
             "Linux truncates process names; use the truncated form, e.g. '${pname:0:15}'"
    fi
done

if (( REC_UI_DEFAULT_INDEX >= 0 && REC_UI_DEFAULT_INDEX < n )); then
    pass "Default UI is ${REC_UI_NAMES[$REC_UI_DEFAULT_INDEX]}"
else
    bad "REC_UI_DEFAULT_INDEX=$REC_UI_DEFAULT_INDEX is out of range" \
        "Set it between 0 and $((n-1)) in config.sh"
fi

if pgrep -f "ui_rotate.sh" >/dev/null 2>&1; then
    pass "The UI watchdog is running"
else
    warn "The UI watchdog is not running" \
         "Normal over SSH - it only starts on the console. Check after a reboot."
fi

running=""
for i in "${!REC_UI_PROCESSES[@]}"; do
    if rec_ui_running "${REC_UI_PROCESSES[$i]}"; then
        running="${REC_UI_NAMES[$i]}"
        break
    fi
done
if [[ -n "$running" ]]; then
    pass "Currently running UI: $running"
else
    warn "No UI is running right now" "Expected if you are only using SSH"
fi
fi

# ===========================================================================
if run_section gpio; then
section "GPIO buttons"

if python3 -c "import RPi.GPIO" 2>/dev/null; then
    # Two conflicting packages provide this; say which, since they behave
    # slightly differently and only one works on a Pi 5.
    gpio_pkg="$(dpkg -S "$(python3 -c 'import RPi.GPIO, os; print(os.path.dirname(RPi.GPIO.__file__))' 2>/dev/null)" 2>/dev/null | cut -d: -f1 | head -1)"
    pass "RPi.GPIO is available${gpio_pkg:+ (from $gpio_pkg)}"

    model="$( { tr -d '\0' < /proc/device-tree/model; } 2>/dev/null )"
    if [[ "$model" == *"Pi 5"* && "$gpio_pkg" == "python3-rpi.gpio" ]]; then
        bad "python3-rpi.gpio does not work on a Raspberry Pi 5" \
            "sudo apt install python3-rpi-lgpio  (it replaces this package)"
    fi
else
    warn "RPi.GPIO is not installed" "./install.sh 60-gpio"
fi

if [[ ${#REC_GPIO_BUTTONS[@]} -gt 0 ]]; then
    pass "${#REC_GPIO_BUTTONS[@]} button(s) configured"
    for entry in "${REC_GPIO_BUTTONS[@]}"; do
        pin="${entry%%:*}"
        cmd="${entry#*:}"
        if [[ "$pin" =~ ^[0-9]+$ ]]; then
            # Verify the command's binary exists - a typo here means a dead
            # button with no error message anywhere.
            read -r -a parts <<<"$cmd"
            # Look past wrappers to the thing that actually has to exist.
            idx=0
            while [[ "${parts[$idx]:-}" =~ ^(sudo|bash|sh|python3)$ ]]; do
                idx=$((idx + 1))
            done
            binary="${parts[$idx]:-}"
            if [[ -z "$binary" ]]; then
                bad "GPIO$pin has no command"
            elif rec_has "$binary" || [[ -f "$binary" ]]; then
                pass "GPIO$pin -> $cmd"
            else
                bad "GPIO$pin -> '$binary' not found" "Fix REC_GPIO_BUTTONS in config.sh"
            fi
        else
            bad "Malformed button entry: $entry" "Use the form PIN:COMMAND"
        fi
    done
else
    warn "No buttons configured" "Set REC_GPIO_BUTTONS in config.sh if you have any"
fi

if pgrep -f "gpio_buttons.py" >/dev/null 2>&1; then
    pass "The button listener is running"
else
    warn "The button listener is not running" \
         "Normal over SSH - it starts from autostart.sh on the console"
fi

if [[ -f /etc/sudoers.d/010_rec-gpio-power ]]; then
    pass "Passwordless shutdown is configured"
else
    warn "The shutdown button will prompt for a password (and therefore fail)" \
         "./install.sh 60-gpio"
fi
fi

# ===========================================================================
if run_section vpn; then
section "NordVPN"

if rec_has nordvpn; then
    pass "NordVPN is installed"

    if systemctl is-active --quiet nordvpnd; then
        pass "nordvpnd is running"
    else
        bad "nordvpnd is not running" "sudo systemctl start nordvpnd"
    fi

    if id -nG "$USER" | grep -qw nordvpn; then
        pass "$USER is in the 'nordvpn' group"
    else
        bad "$USER is not in the 'nordvpn' group" \
            "sudo usermod -aG nordvpn $USER, then log out and back in"
    fi

    if nordvpn account >/dev/null 2>&1; then
        pass "Logged in to NordVPN"
        status="$(nordvpn status 2>/dev/null)"
        if grep -q "Status: Connected" <<<"$status"; then
            pass "Connected: $(grep -i '^ *Hostname:' <<<"$status" | cut -d: -f2- | xargs)"
        else
            warn "VPN is disconnected" "Expected if 'xx' is first in NORDVPN_COUNTRIES"
        fi

        if nordvpn settings 2>/dev/null | grep -qi "meshnet: enabled"; then
            pass "Meshnet is enabled"
        else
            warn "Meshnet is disabled" "nordvpn set meshnet on"
        fi

        # The allowlist is what keeps SSH alive while the tunnel is up.
        if nordvpn settings 2>/dev/null | grep -qF "${NORDVPN_LAN_SUBNET:-__none__}"; then
            pass "LAN subnet ${NORDVPN_LAN_SUBNET} is allowlisted"
        else
            bad "LAN subnet ${NORDVPN_LAN_SUBNET:-<unset>} is NOT allowlisted" \
                "SSH will drop when the VPN connects. Run: ./install.sh 70-nordvpn"
        fi
    else
        warn "Not logged in to NordVPN" "Set NORDVPN_TOKEN in config.sh, then ./install.sh 70-nordvpn"
    fi

    # Check the configured subnet actually matches this machine.
    my_ip="$(hostname -I | awk '{print $1}')"
    if [[ -n "$my_ip" && -n "${NORDVPN_LAN_SUBNET:-}" ]]; then
        if [[ "${NORDVPN_LAN_SUBNET%.*/*}" == "${my_ip%.*}" ]]; then
            pass "NORDVPN_LAN_SUBNET matches this Pi's address ($my_ip)"
        else
            bad "This Pi is at $my_ip but NORDVPN_LAN_SUBNET is $NORDVPN_LAN_SUBNET" \
                "Correct NORDVPN_LAN_SUBNET in config.sh"
        fi
    fi

    if [[ -n "${NORDVPN_TOKEN:-}" ]]; then
        pass "NORDVPN_TOKEN is set"
    else
        warn "NORDVPN_TOKEN is empty" "Automatic login at boot will not work"
    fi
else
    warn "NordVPN is not installed" "./install.sh 70-nordvpn"
fi
fi

# ===========================================================================
if run_section net; then
section "Networking"

if rec_online; then
    pass "Internet is reachable"
else
    bad "No internet connection" "Speech and streaming will not work"
fi

if rec_has socat; then
    pass "socat is installed"
    if [[ ${#REC_PORT_FORWARDS[@]} -gt 0 ]]; then
        for entry in "${REC_PORT_FORWARDS[@]}"; do
            IFS=':' read -r lp th tp <<<"$entry"
            if [[ -z "$lp" || -z "$th" || -z "$tp" ]]; then
                bad "Malformed forward: $entry" "Use PORT:HOST:PORT"
                continue
            fi
            if ss -tlnH "sport = :$lp" 2>/dev/null | grep -q .; then
                pass "Port $lp is listening (-> $th:$tp)"
            else
                warn "Port $lp is not listening" \
                     "Start it with: bash $REC_BIN/port_forwarding.sh &"
            fi
        done
    else
        warn "No port forwards configured" "Set REC_PORT_FORWARDS in config.sh if you want any"
    fi
else
    warn "socat is not installed" "./install.sh 75-port-forwarding"
fi
fi

# ===========================================================================
if run_section web; then
section "Web server"

if rec_has apache2; then
    if systemctl is-active --quiet apache2; then
        pass "Apache is running"
    else
        bad "Apache is installed but not running" "sudo systemctl start apache2"
    fi

    if [[ -f /var/www/html/info.php ]]; then
        bad "/var/www/html/info.php is published" \
            "It leaks version information. Remove it: sudo rm /var/www/html/info.php"
    else
        pass "No phpinfo page is exposed"
    fi

    if systemctl is-active --quiet noip2; then
        pass "No-IP client is running"
    else
        warn "No-IP client is not running" "Your hostname may point at a stale IP"
    fi

    if [[ -d /etc/letsencrypt/live ]]; then
        pass "An HTTPS certificate is installed"
        if systemctl is-enabled --quiet certbot.timer 2>/dev/null; then
            pass "Automatic renewal is enabled"
        else
            bad "Certificate renewal is not scheduled" "sudo systemctl enable --now certbot.timer"
        fi
    else
        warn "No HTTPS certificate" "sudo certbot --apache"
    fi

    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        pass "Automatic security updates are enabled"
    else
        bad "Automatic security updates are NOT enabled" \
            "This Pi is internet-facing. Run: ./install.sh 80-webserver"
    fi
else
    warn "Apache is not installed" "Only needed if you want a public web server"
fi
fi

# ===========================================================================
if run_section audio; then
section "Audio and speech"

if rec_has mpg123; then
    pass "mpg123 is installed"
else
    bad "mpg123 is not installed" "./install.sh 90-speech"
fi

if aplay -l 2>/dev/null | grep -q '^card'; then
    pass "A sound card is present"
else
    bad "No sound card detected" "See docs/90-speech.md"
fi

# Volume is a chain of multiplications - Kodi x stream x sink x ALSA - so a
# single link left low makes everything quiet no matter what the others say.
if rec_has wpctl; then
    sink_vol="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'Volume: \K[0-9.]+')"
    if [[ -n "$sink_vol" ]]; then
        # bash has no floats; compare in hundredths.
        vol_pct="$(awk -v v="$sink_vol" 'BEGIN{printf "%d", v*100}')"
        if (( vol_pct >= 90 )); then
            pass "PipeWire sink volume ${vol_pct}%"
        else
            warn "PipeWire sink volume is only ${vol_pct}%" \
                 "wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%"
        fi
        if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED; then
            bad "The default audio sink is MUTED" "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"
        fi
    fi
fi

if rec_has amixer; then
    # The Pi's analogue control is PCM; other cards vary, so try a couple.
    for ctl in PCM Master Headphone; do
        raw="$(amixer sget "$ctl" 2>/dev/null | grep -oP '\[\K[0-9]+(?=%\])' | head -1)"
        [[ -n "$raw" ]] || continue
        # On a PipeWire system WirePlumber owns this control and re-applies its
        # own value at startup, so amixer/alsactl changes do not survive a
        # reboot. Recommend the tool that actually persists.
        if rec_has wpctl && pgrep -x pipewire >/dev/null 2>&1; then
            if (( raw >= 90 )); then
                pass "ALSA '$ctl' at ${raw}% (managed by WirePlumber)"
            else
                warn "ALSA '$ctl' is at ${raw}%" \
                     "Set it via wpctl, not amixer: wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%"
            fi
        else
            if (( raw >= 90 )); then
                pass "ALSA '$ctl' at ${raw}%"
            else
                warn "ALSA '$ctl' is at ${raw}%" \
                     "amixer sset $ctl 100% && sudo alsactl store"
            fi
        fi
        break
    done
fi

# A level set with amixer on a PipeWire system reverts at the next boot,
# which is a confusing failure if you do not know what owns the mixer.
if rec_has wpctl && pgrep -x pipewire >/dev/null 2>&1; then
    wp_state="$HOME/.local/state/wireplumber"
    if [[ -d "$wp_state" ]]; then
        pass "WirePlumber state present ($wp_state) - wpctl volumes persist"
    else
        warn "No WirePlumber state directory yet" \
             "Set the volume once with wpctl so it is remembered across reboots"
    fi
fi

# The Pi's analogue output is PWM, not a DAC. audio_pwm_mode=2 selects the
# improved modulation and is a real quality difference on the 3.5 mm jack.
BOOTCFG=/boot/firmware/config.txt
[[ -f "$BOOTCFG" ]] || BOOTCFG=/boot/config.txt
if [[ -f "$BOOTCFG" ]] && grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    if grep -qE '^\s*audio_pwm_mode=2' "$BOOTCFG"; then
        pass "audio_pwm_mode=2 (improved analogue output)"
    else
        warn "audio_pwm_mode=2 is not set in $BOOTCFG" \
             "Improves 3.5 mm jack quality noticeably; add it and reboot"
    fi
fi

sound="${ACTION_SOUND:-}"
if [[ -z "$sound" ]]; then
    warn "ACTION_SOUND is empty" "Button presses give no audible confirmation"
else
    [[ "$sound" == /* ]] || sound="$REC_ASSETS/sounds/$sound"
    if [[ -f "$sound" ]]; then
        pass "Action sound found"
    else
        bad "Action sound not found: $sound" "Fix ACTION_SOUND in config.sh"
    fi
fi

if [[ "${VOLUME:-100}" =~ ^[0-9]+$ ]] && (( VOLUME >= 0 && VOLUME <= 100 )); then
    pass "VOLUME is ${VOLUME}%"
else
    bad "VOLUME='${VOLUME:-}' is not a percentage between 0 and 100" "Fix it in config.sh"
fi
fi

# ===========================================================================
if run_section bluetooth; then
section "Bluetooth speaker"

if rec_has bluetoothctl; then
    pass "bluez is installed"

    systemctl is-active --quiet bluetooth \
        && pass "bluetooth.service is running" \
        || bad "bluetooth.service is not running" "sudo systemctl enable --now bluetooth"

    if dpkg-query -W -f='${Status}' pulseaudio-module-bluetooth 2>/dev/null | grep -q "ok installed"; then
        pass "pulseaudio-module-bluetooth is installed"
    else
        bad "pulseaudio-module-bluetooth is missing" "./install.sh 85-bluetooth"
    fi

    btshow="$(bluetoothctl show 2>/dev/null)"

    # Phones decide whether to offer "media audio" from the device class. The
    # Pi ships as a computer (0x000c/0x002c...), and many phones will then
    # pair but never route audio.
    class="$(grep -i '^\s*Class:' <<<"$btshow" | awk '{print $2}')"
    case "$class" in
        0x2*|0x24*)  pass "Advertised as an audio device ($class)" ;;
        "")          warn "Could not read the device class" "Is the adapter powered?" ;;
        *)           bad "Device class is $class, not an audio device" \
                         "Phones may refuse to send audio. Run: ./install.sh 85-bluetooth" ;;
    esac

    grep -qi 'Discoverable: yes' <<<"$btshow" \
        && pass "Discoverable (phones can find it)" \
        || warn "Not discoverable - already-paired devices still work" \
                "sudo systemctl restart bt-agent"

    grep -qi 'Audio Sink' <<<"$btshow" \
        && pass "Audio Sink profile is advertised (can receive audio)" \
        || bad "No Audio Sink profile" "The Pi cannot act as a speaker: ./install.sh 85-bluetooth"

    if rec_has bt-agent; then
        pass "bt-agent is installed"
        systemctl is-active --quiet bt-agent \
            && pass "bt-agent is running (pairing needs no keyboard)" \
            || bad "bt-agent is not running" "sudo systemctl enable --now bt-agent"
    else
        bad "bt-agent is not installed" \
            "Pairing cannot be confirmed without it: ./install.sh 85-bluetooth"
    fi

    paired="$(bluetoothctl devices 2>/dev/null | grep -c '^Device')"
    (( paired > 0 )) && pass "$paired device(s) paired" \
                     || warn "No paired devices yet" "Pair a phone - see docs/85-bluetooth.md"

    # System mode is what keeps this working outside a desktop session.
    if systemctl is-enabled --quiet pulseaudio 2>/dev/null; then
        pass "System-mode PulseAudio is enabled (works under Kodi and the console)"
        systemctl is-active --quiet pulseaudio \
            && pass "System-mode PulseAudio is running" \
            || bad "Enabled but not running" "sudo journalctl -u pulseaudio -n 30"

        # The classic silent failure: system.pa omits the Bluetooth modules
        # that default.pa loads, so audio pairs but never reaches the jack.
        if grep -q "module-bluetooth-discover" /etc/pulse/system.pa 2>/dev/null; then
            pass "system.pa loads the Bluetooth modules"
        else
            bad "system.pa does NOT load the Bluetooth modules" \
                "Phones will connect but no sound will play. Run: ./install.sh 85-bluetooth"
        fi
    elif pgrep -u "$USER" pulseaudio >/dev/null 2>&1; then
        warn "PulseAudio is per-user: works on the desktop, silent under Kodi" \
             "For console and Kodi audio: ./install.sh 85-bluetooth"
    else
        warn "No PulseAudio daemon is running" "Normal over SSH with no desktop session"
    fi

    # Output should be the analogue jack, not HDMI.
    sinks="$(pactl list sinks short 2>/dev/null)"
    if [[ -n "$sinks" ]]; then
        grep -qi 'analog' <<<"$sinks" \
            && pass "An analogue (jack) output is available" \
            || warn "No analogue sink found - audio may be routed to HDMI" \
                    "sudo raspi-config nonint do_audio 1"
    fi
else
    warn "Bluetooth tools are not installed" "./install.sh 85-bluetooth"
fi
fi

# ===========================================================================
if run_section weather; then
section "Weather"

if [[ -n "${OPENWEATHER_API_KEY:-}" ]]; then
    pass "OPENWEATHER_API_KEY is $(masked "$OPENWEATHER_API_KEY")"

    location="${REC_WEATHER_LOCATION:-auto}"
    if [[ "$location" == "auto" ]]; then
        pass "Location: auto (detected from the public IP)"
        # Auto-detection follows the VPN exit node, which on this system
        # moves between countries. Worth saying out loud.
        if rec_has nordvpn && nordvpn status 2>/dev/null | grep -q "Status: Connected"; then
            warn "The VPN is connected, so 'auto' reports the exit country" \
                 "Set REC_WEATHER_LOCATION to a city or \"lat,lon\" in config.sh"
        fi
    else
        pass "Location: $location"
    fi

    if [[ "${REC_WEATHER_UNITS:-metric}" =~ ^(metric|imperial)$ ]]; then
        pass "Units: ${REC_WEATHER_UNITS:-metric}"
    else
        bad "REC_WEATHER_UNITS='${REC_WEATHER_UNITS}' is invalid" \
            "Use \"metric\" or \"imperial\""
    fi
else
    warn "OPENWEATHER_API_KEY is empty" \
         "Only needed for the weather module - see docs/95-weather.md"
fi
fi

# ===========================================================================
if run_section base; then
section "Hardware"

if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
    if (( temp < 70 )); then
        pass "CPU temperature ${temp}C"
    elif (( temp < 80 )); then
        warn "CPU temperature ${temp}C" "Getting warm - check ventilation"
    else
        bad "CPU temperature ${temp}C" "The Pi throttles at 80C - improve cooling"
    fi
fi

if rec_has vcgencmd; then
    throttled="$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)"
    if [[ "$throttled" == "0x0" ]]; then
        pass "No throttling or under-voltage recorded"
    else
        # Decode the bitmask rather than printing hex at the user. Bits 0-3
        # mean "happening right now"; bits 16-19 mean "has happened since
        # boot", which is the more common and more confusing case.
        v=$(( throttled ))
        now=(); past=()
        (( v & 0x1 ))     && now+=("under-voltage")
        (( v & 0x2 ))     && now+=("ARM frequency capped")
        (( v & 0x4 ))     && now+=("currently throttled")
        (( v & 0x8 ))     && now+=("soft temperature limit active")
        (( v & 0x10000 )) && past+=("under-voltage")
        (( v & 0x20000 )) && past+=("ARM frequency capped")
        (( v & 0x40000 )) && past+=("throttled")
        (( v & 0x80000 )) && past+=("soft temperature limit reached")

        if (( ${#now[@]} > 0 )); then
            bad "Happening right now: ${now[*]}" \
                "Replace the power supply (2.5A+) and improve cooling - the Pi is degraded as you read this."
        fi
        if (( ${#past[@]} > 0 )); then
            bad "Has occurred since boot: ${past[*]} ($throttled)" \
                "Almost always an inadequate power supply. See docs/HARDWARE.md."
        fi
    fi
fi

avail_mb=$(df -m / | awk 'NR==2{print $4}')
if (( avail_mb > 2000 )); then
    pass "${avail_mb} MB free on /"
elif (( avail_mb > 500 )); then
    warn "${avail_mb} MB free on /" "Getting tight - Kodi thumbnails grow quickly"
else
    bad "Only ${avail_mb} MB free on /" "Clear space: sudo apt-get clean; rm -rf ~/.kodi/temp/*"
fi
fi

# ===========================================================================
printf '\n%s%s%s\n' "$C_BOLD" "$(printf '%.0s=' {1..60})" "$C_OFF"
printf '%sPassed: %d   Warnings: %d   Failures: %d%s\n' "$C_BOLD" "$PASS" "$WARN" "$FAIL" "$C_OFF"

if (( FAIL > 0 )); then
    printf '\n%sFix the FAIL lines above.%s Each one lists the command to run.\n' "$C_RED" "$C_OFF"
    printf 'More detail in docs/TROUBLESHOOTING.md\n'
    exit 1
elif (( WARN > 0 )); then
    printf '\nNo failures. The warnings are usually fine - check them if something feels off.\n'
    exit 0
else
    printf '\n%sEverything checks out.%s\n' "$C_GREEN" "$C_OFF"
    exit 0
fi
