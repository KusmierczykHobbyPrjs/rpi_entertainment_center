#!/bin/bash
# ---------------------------------------------------------------------------
# doctor.sh - check that everything is installed and configured correctly.
#
# Run this after installing, after changing config.sh, and first thing when
# something stops working. It only reads state - it changes nothing.
#
#   doctor.sh              check everything
#   doctor.sh vpn          check one section (base|kodi|ui|gpio|vpn|net|web|audio)
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
        pass "${REC_UI_NAMES[$i]} -> $binary"
    else
        bad "${REC_UI_NAMES[$i]} -> $binary is not installed" \
            "Install it, or remove index $i from all four arrays in config.sh"
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
    if pgrep -x "${REC_UI_PROCESSES[$i]}" >/dev/null 2>&1; then
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
    pass "RPi.GPIO is available"
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
