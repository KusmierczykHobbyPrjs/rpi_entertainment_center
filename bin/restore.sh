#!/bin/bash
# ---------------------------------------------------------------------------
# restore.sh - put back what backup.sh saved.
#
#   restore.sh <archive>              restore everything in it
#   restore.sh <archive> --list       show what is inside, change nothing
#   restore.sh <archive> --safe       only version-independent files
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
SAFE_ONLY=0
ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    LIST_ONLY=1 ;;
        --safe)    SAFE_ONLY=1 ;;
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
# The version-independent subset: plain data no software version cares about.
# Deliberately excludes emulators.cfg (absolute core paths), the Kodi
# databases (schema-versioned) and Widevine (architecture and version tied).
SAFE_PATTERN='retroarch/autoconfig|retroarch-joypads|es_input.cfg|es_settings.cfg|gamelists|config.sh|rec-iptv|sources.xml|favourites.xml|advancedsettings.xml|mediasources.xml|profiles.xml'

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

# --- Version drift ---------------------------------------------------------
# Most of the archive is plain data that does not care what version reads it.
# Two things do, and they fail in different ways, so check both explicitly.
mf="$(tar xzOf "$ARCHIVE" MANIFEST.txt 2>/dev/null)"
was_kodi="$(grep -oP '^\s*kodi:\s*\K\S+'       <<<"$mf" 2>/dev/null)"
was_kodidb="$(grep -oP '^\s*kodi_db:\s*\K\S+'  <<<"$mf" 2>/dev/null)"
was_retropie="$(grep -oP '^\s*retropie:\s*\K\S+' <<<"$mf" 2>/dev/null)"
was_bt="$(grep -oP '^\s*bt_adapter:\s*\K\S+'   <<<"$mf" 2>/dev/null)"

now_kodi="$(dpkg-query -W -f='${Version}' kodi 2>/dev/null)"
now_kodidb="$(ls "$HOME/.kodi/userdata/Database"/MyVideos*.db 2>/dev/null | head -1 | grep -oP 'MyVideos\K[0-9]+')"
now_retropie="$(cat /opt/retropie/VERSION 2>/dev/null)"
now_bt="$(sudo ls /var/lib/bluetooth 2>/dev/null | head -1)"

drift=0

# Kodi: the number in MyVideos<N>.db IS the schema version. Kodi migrates an
# older database forward on first start. It cannot go backwards - an older
# Kodi simply ignores a newer file and starts with an empty library.
if [[ -n "$was_kodidb" && -n "$now_kodidb" && "$was_kodidb" != "$now_kodidb" ]]; then
    drift=1
    if (( was_kodidb < now_kodidb )); then
        rec_log "Kodi database schema $was_kodidb -> $now_kodidb (newer Kodi)."
        rec_log "  Kodi will migrate the library forward on first start. This is fine."
    else
        rec_warn "Archive holds Kodi schema $was_kodidb but this Kodi uses $now_kodidb."
        rec_warn "  That is a DOWNGRADE. Kodi cannot migrate backwards - it will"
        rec_warn "  ignore the restored library and start empty. Your watched states"
        rec_warn "  and library would be lost. Consider --only config instead."
    fi
elif [[ -n "$was_kodi" && -n "$now_kodi" && "$was_kodi" != "$now_kodi" ]]; then
    drift=1
    rec_log "Kodi $was_kodi -> $now_kodi. Settings migrate forward; unknown keys are ignored."
fi

# RetroPie: emulators.cfg hardcodes absolute paths to libretro cores. Install
# a different emulator set and those paths point at nothing, which shows up as
# a game that simply refuses to launch.
if [[ -n "$was_retropie" && -n "$now_retropie" && "$was_retropie" != "$now_retropie" ]]; then
    drift=1
    rec_warn "RetroPie $was_retropie -> $now_retropie."
    rec_warn "  emulators.cfg refers to cores by absolute path. Any core you did not"
    rec_warn "  reinstall will fail to launch. This script checks for that afterwards."
fi

# Bluetooth link keys live under the adapter's own MAC address, so they only
# mean anything on the same physical hardware.
if [[ -n "$was_bt" && -n "$now_bt" && "$was_bt" != "$now_bt" ]]; then
    drift=1
    rec_warn "Bluetooth adapter $was_bt -> $now_bt (different hardware)."
    rec_warn "  Pairing keys will not apply; devices must be paired again."
fi

(( drift == 1 )) && echo

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
declare -a stopped=()
if [[ $SAFE_ONLY -eq 1 ]]; then
    pattern="$SAFE_PATTERN"
    rec_log "Safe mode: only version-independent files"
fi

if [[ -n "$pattern" ]]; then
    # Keep only the topmost path of each branch.
    #
    # tar already extracts a directory member's entire subtree, so listing the
    # descendants as well makes it report every one of them as "Not found in
    # archive" once it has passed them. '--only retropie' matched 239 paths,
    # the first of which was the directory opt/retropie/configs/ - and printed
    # 267 error lines after a restore that had in fact put everything back.
    # Nobody reads that and concludes "it worked".
    mapfile -t members < <(
        tar tzf "$ARCHIVE" | grep -E "$pattern" | sort | awk '
            prefix == "" || index($0, prefix) != 1 {
                print
                prefix = ($0 ~ /\/$/) ? $0 : $0 "/"
            }'
    )
    if [[ ${#members[@]} -eq 0 ]]; then
        rec_die "Nothing matching '--only $ONLY' found in the archive."
    fi
    rec_log "Restoring ${#members[@]} path(s) matching '${ONLY:-safe}'"
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
tar_status=$?

# Say so honestly. The old version printed "Files restored" whatever tar did.
if (( tar_status == 0 )); then
    rec_log "Files restored"
else
    rec_warn "tar exited with status $tar_status - not everything was restored."
    rec_warn "  See what the archive actually holds: $REC_BIN/restore.sh '$ARCHIVE' --list"
fi

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

# --- Validate what we just put back ----------------------------------------
# emulators.cfg names cores by absolute path. After a reinstall with a
# different emulator set those paths can point at nothing, and the only
# symptom is a game that refuses to start with no useful error.
if [[ -d /opt/retropie/configs ]]; then
    missing_cores=()
    while IFS= read -r core; do
        [[ -e "$core" ]] || missing_cores+=("$core")
    done < <(grep -rhoE '/opt/retropie/libretrocores/[^ "]+\.so' \
                 /opt/retropie/configs/*/emulators.cfg 2>/dev/null | sort -u)

    if (( ${#missing_cores[@]} > 0 )); then
        echo
        rec_warn "${#missing_cores[@]} emulator core(s) referenced by the restored"
        rec_warn "configs are not installed on this system:"
        printf '    %s\n' "${missing_cores[@]}" | head -10
        (( ${#missing_cores[@]} > 10 )) && echo "    ... and $(( ${#missing_cores[@]} - 10 )) more"
        rec_warn "Games set to use them will not launch. Either install them:"
        rec_warn "    sudo ~/RetroPie-Setup/retropie_setup.sh   (Manage packages)"
        rec_warn "or pick a different emulator per system by holding a button at"
        rec_warn "launch, which rewrites emulators.cfg."
    else
        rec_log "All emulator cores referenced by the restored configs are present."
    fi
fi

for svc in "${stopped[@]}"; do
    rec_log "Starting $svc"
    sudo systemctl start "$svc" 2>/dev/null
done

sudo systemctl daemon-reload

cat <<EOF

Restored. Now:

  1. Check everything:        $REC_BIN/doctor.sh
  2. Reboot, so the restored services and Bluetooth pairings take effect:
                              sudo reboot

If you restored RetroPie configs, your scraped gamelists are back and
EmulationStation will pick them up at next start.

If EmulationStation still asks you to configure the controller, the mapping
was restored but its SDL GUID no longer matches - the GUID includes a hash of
the pad's name, and SDL changed how it derives that. Relink it instead of
mapping every button again:

  python3 $REC_BIN/controller_relink.py            # show what would change
  python3 $REC_BIN/controller_relink.py --apply
EOF
