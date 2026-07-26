#!/bin/bash
# ---------------------------------------------------------------------------
# restore.sh - put back what backup.sh saved.
#
#   restore.sh <archive>              restore everything in it
#   restore.sh <archive> --list       show what is inside, change nothing
#   restore.sh <archive> --only retropie|kodi|config|bluetooth|tvheadend|noip|content
#
# Order matters: install the modules FIRST, then restore. Installing over a
# restored config will overwrite it, and RetroPie in particular recreates
# /opt/retropie/configs during its own setup.
#
# See docs/BACKUP.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ARCHIVE=""
LIST_ONLY=0
ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    LIST_ONLY=1 ;;
        --only)    ONLY="${2:-}"; shift ;;
        -h|--help) sed -n '3,13p' "$(readlink -f "$0")" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        rec_die "Unknown option: $1" ;;
        *)         ARCHIVE="$1" ;;
    esac
    shift
done

[[ -n "$ARCHIVE" ]] || rec_die "Usage: restore.sh <archive> [--list] [--only NAME]"
[[ -f "$ARCHIVE" ]] || rec_die "No such archive: $ARCHIVE"

# Which paths inside the archive each --only name covers.
case "$ONLY" in
    "")          pattern="" ;;
    retropie)    pattern="opt/retropie/configs" ;;
    kodi)        pattern="home/*/.kodi/userdata" ;;
    config)      pattern="*config.sh" ;;
    bluetooth)   pattern="etc/bluetooth|var/lib/bluetooth" ;;
    tvheadend)   pattern="home/hts" ;;
    noip)        pattern="no-ip2.conf|noip2.service" ;;
    content)     pattern="RetroPie/roms|RetroPie/BIOS|var/www" ;;
    *)           rec_die "Unknown --only value: $ONLY" ;;
esac

# --- Show the manifest -----------------------------------------------------
rec_log "Archive: $ARCHIVE"
echo
if tar xzOf "$ARCHIVE" MANIFEST.txt 2>/dev/null; then
    echo
else
    rec_warn "No manifest inside - this may not be a backup.sh archive."
fi

if [[ $LIST_ONLY -eq 1 ]]; then
    echo "Contents:"
    tar tzf "$ARCHIVE" | awk -F/ '{print $1"/"$2"/"$3}' | sort -u | sed 's|^|  /|'
    exit 0
fi

# --- Warn about ordering ---------------------------------------------------
cat <<EOF
Restoring will OVERWRITE the current versions of these files.

Install the modules you want BEFORE restoring, not after - RetroPie's setup
recreates /opt/retropie/configs, and the installers rewrite config.sh.

EOF
read -r -p "Continue? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Nothing restored."; exit 0; }

# --- Restore ---------------------------------------------------------------
# Extracting to / needs root for the system paths. Keep permissions and
# ownership as recorded, so Bluetooth link keys and hts files stay usable.
declare -a members=()
if [[ -n "$pattern" ]]; then
    mapfile -t members < <(tar tzf "$ARCHIVE" | grep -E "$pattern" || true)
    if [[ ${#members[@]} -eq 0 ]]; then
        rec_die "Nothing matching '--only $ONLY' found in the archive."
    fi
    rec_log "Restoring ${#members[@]} path(s) matching '$ONLY'"
else
    rec_log "Restoring everything"
fi

# Stop services that hold the files we are about to replace, so they reload
# cleanly rather than writing their in-memory state back over the restore.
for svc in kodi tvheadend bt-agent pulseaudio; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        rec_log "Stopping $svc"
        sudo systemctl stop "$svc"
        stopped+=("$svc")
    fi
done

if [[ ${#members[@]} -gt 0 ]]; then
    sudo tar xzf "$ARCHIVE" -C / --same-owner --same-permissions "${members[@]}"
else
    sudo tar xzf "$ARCHIVE" -C / --same-owner --same-permissions \
        --exclude=MANIFEST.txt
fi
rec_log "Files restored"

# config.sh must stay private - it carries the VPN token.
[[ -f "$REC_ROOT/config.sh" ]] && chmod 600 "$REC_ROOT/config.sh"

# The archive may come from a different user or repository location, in which
# case paths baked into config.sh no longer point anywhere real.
if [[ -f "$REC_ROOT/config.sh" ]]; then
    if grep -q '/home/[^/]*/' "$REC_ROOT/config.sh" 2>/dev/null; then
        old_home="$(grep -o '/home/[^/]*/' "$REC_ROOT/config.sh" | head -1 | sed 's|/$||')"
        if [[ "$old_home" != "$HOME" ]]; then
            rec_warn "config.sh references $old_home but your home is $HOME"
            rec_warn "Check the paths in it: nano $REC_ROOT/config.sh"
        fi
    fi
fi

for svc in "${stopped[@]:-}"; do
    [[ -n "$svc" ]] || continue
    rec_log "Starting $svc"
    sudo systemctl start "$svc" 2>/dev/null
done

sudo systemctl daemon-reload

cat <<EOF

Restored. Now:

  1. Check everything:        $REC_BIN/doctor.sh
  2. Reboot, so the restored services and Bluetooth pairings take effect:
                              sudo reboot

If you restored RetroPie configs, your controller mapping and scraped
gamelists are back - EmulationStation will pick them up at next start.
EOF
