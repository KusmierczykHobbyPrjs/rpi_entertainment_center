#!/bin/bash
# ---------------------------------------------------------------------------
# backup.sh - save everything a reinstall would otherwise lose.
#
#   backup.sh                     settings only (small, seconds)
#   backup.sh --with-content      settings + ROMs, BIOS, web content (GBs)
#   backup.sh --list              show what would be included, and its size
#   backup.sh /mnt/usb            write the archive somewhere else
#
# Two tiers, because they have very different sizes and very different
# consequences if lost:
#
#   settings  a few hundred KB of things that took real work - controller
#             mappings, scraped game metadata, Kodi library and add-on
#             settings, your config.sh, Bluetooth pairings
#   content   gigabytes of things you probably still have the originals of -
#             ROMs, BIOS images, web server files
#
# Restore with: restore.sh <archive>
# See docs/BACKUP.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

WITH_CONTENT=0
LIST_ONLY=0
DEST="$HOME/rec-backups"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-content) WITH_CONTENT=1 ;;
        --list)         LIST_ONLY=1 ;;
        -h|--help)      sed -n '3,20p' "$(readlink -f "$0")" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)             rec_die "Unknown option: $1" ;;
        *)              DEST="$1" ;;
    esac
    shift
done

# --- What to save ----------------------------------------------------------
# Paths are collected relative to / so restore can put them back exactly.
# Anything absent is skipped silently - not every module is installed.

settings_paths=(
    # RetroPie: emulator configs, controller mappings, EmulationStation
    # settings and scraped gamelists. Small, and painful to recreate.
    "/opt/retropie/configs"

    # Kodi: library database, add-on settings, favourites, sources, and the
    # add-on data directory that holds things like the Netflix auth key.
    "$HOME/.kodi/userdata"

    # The active Widevine module. Only ~9 MB, and re-obtaining it through
    # inputstreamhelper is one of the more failure-prone steps of a rebuild,
    # so it earns its place.
    "$HOME/.kodi/cdm"

    # This project's own settings and secrets.
    "$REC_ROOT/config.sh"

    # IPTV playlists, including any channels you added by hand.
    "$HOME/.local/share/rec-iptv"

    # Bluetooth: device class, discoverability, and the pairing link keys -
    # without these every phone has to be paired again.
    "/etc/bluetooth/main.conf"
    "/var/lib/bluetooth"

    # Services this project installs.
    "/etc/systemd/system/pulseaudio.service"
    "/etc/systemd/system/bt-agent.service"
    "/etc/systemd/system/noip2.service"

    # Dynamic DNS credentials and hostname.
    "/usr/local/etc/no-ip2.conf"

    # Tvheadend: channel line-up, EPG config, users.
    "/home/hts/.hts"
)

content_paths=(
    "$HOME/RetroPie/roms"
    "$HOME/RetroPie/BIOS"
    "/var/www/html"
)

# Excluded from inside the paths above: bulky, regenerable, or shipped by the
# distribution rather than created by you.
excludes=(
    --exclude="*/retroarch/assets"        # shipped with retroarch
    --exclude="*/retroarch/shaders"
    --exclude="*/retroarch/overlays"
    --exclude="*/retroarch/cores"
    --exclude="*/downloaded_images"       # scraped art, re-scrapeable
    --exclude="*/downloaded_media"
    --exclude="*/.kodi/userdata/Thumbnails"
    --exclude="*/Database/Textures*.db"   # Kodi thumbnail cache

    # inputstreamhelper keeps copies of every Widevine version it has ever
    # installed. The active one is backed up separately from ~/.kodi/cdm;
    # these were 27 MB of superseded duplicates.
    --exclude="*/script.module.inputstreamhelper/backup"

    # Add-ons that download their own binaries at runtime. They re-fetch
    # them; there is no point carrying 10 MB of executable around.
    --exclude="*/plugin.video.torrest/bin"

    # Add-on HTTP and metadata caches - all regenerable, and stale caches
    # cause more trouble after a restore than they save.
    --exclude="*_cache.sqlite"
    --exclude="*_cache.sqlite-*"
    --exclude="*/nf_cache.sqlite3"
    --exclude="*/cache"

    --exclude="*.log"
    --exclude="*.log.bak"
)

# --- Helpers ---------------------------------------------------------------

# Some of the above is root-owned (/var/lib/bluetooth, /home/hts). Use sudo
# only when we actually cannot read a path ourselves.
needs_sudo() {
    local p
    for p in "$@"; do
        [[ -e "$p" ]] && [[ ! -r "$p" ]] && return 0
    done
    return 1
}

present=()
for p in "${settings_paths[@]}"; do [[ -e "$p" ]] && present+=("$p"); done
if [[ $WITH_CONTENT -eq 1 ]]; then
    for p in "${content_paths[@]}"; do [[ -e "$p" ]] && present+=("$p"); done
fi

if [[ ${#present[@]} -eq 0 ]]; then
    rec_die "Nothing to back up - is anything installed yet?"
fi

# --- List mode -------------------------------------------------------------
if [[ $LIST_ONLY -eq 1 ]]; then
    echo "Would include:"
    for p in "${present[@]}"; do
        size="$(sudo du -sh --exclude=downloaded_images --exclude=assets \
                   --exclude=shaders --exclude=overlays --exclude=Thumbnails \
                   "$p" 2>/dev/null | cut -f1)"
        printf '  %-8s %s\n' "${size:-?}" "$p"
    done
    echo
    if [[ $WITH_CONTENT -eq 0 ]]; then
        echo "Not included (add --with-content):"
        for p in "${content_paths[@]}"; do
            [[ -e "$p" ]] || continue
            size="$(du -sh "$p" 2>/dev/null | cut -f1)"
            printf '  %-8s %s\n' "${size:-?}" "$p"
        done
    fi
    exit 0
fi

# --- Create the archive ----------------------------------------------------
mkdir -p "$DEST" || rec_die "Cannot write to $DEST"
stamp="$(date +%Y%m%d-%H%M%S)"
suffix="settings"
[[ $WITH_CONTENT -eq 1 ]] && suffix="full"
archive="$DEST/rec-backup-${suffix}-${stamp}.tar.gz"

rec_log "Backing up ${#present[@]} location(s) to $archive"

# A manifest travels inside the archive so restore - and you, a year from now -
# can see what it holds and which version wrote it.
manifest="$(mktemp)"
{
    echo "# rpi-entertainment-center backup"
    echo "created:  $(date -Iseconds)"
    echo "host:     $(hostname)"
    echo "user:     $USER"
    echo "repo:     $REC_ROOT"
    echo "tier:     $suffix"
    echo "os:       $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    command -v git >/dev/null && [[ -d "$REC_ROOT/.git" ]] && \
        echo "commit:   $(git -C "$REC_ROOT" rev-parse --short HEAD 2>/dev/null)"
    echo "paths:"
    printf '  %s\n' "${present[@]}"
} > "$manifest"

TAR=(tar czf "$archive" "${excludes[@]}"
     --transform="s|^$(echo "$manifest" | sed 's|^/||')|MANIFEST.txt|"
     -C / "${present[@]#/}" "${manifest#/}")

if needs_sudo "${present[@]}"; then
    rec_log "Some paths are root-owned; using sudo"
    sudo "${TAR[@]}" 2>&1 | grep -v 'Removing leading' || true
    sudo chown "$USER:$USER" "$archive"
else
    "${TAR[@]}" 2>&1 | grep -v 'Removing leading' || true
fi
rm -f "$manifest"

if [[ ! -f "$archive" ]]; then
    rec_die "Backup failed - no archive was written."
fi

# config.sh holds your VPN token and API keys, so the archive does too.
chmod 600 "$archive"

size="$(du -h "$archive" | cut -f1)"
rec_log "Done: $archive ($size)"

cat <<EOF

  The archive contains config.sh, so it holds your VPN token and API keys.
  It is mode 600 for that reason - keep it somewhere you trust.

  Copy it off this machine before reinstalling:

      scp $USER@$(hostname):$archive .

  Restore afterwards with:

      bin/restore.sh $(basename "$archive")

EOF
if [[ $WITH_CONTENT -eq 0 ]] && [[ -d "$HOME/RetroPie/roms" ]]; then
    roms_size="$(du -sh "$HOME/RetroPie/roms" 2>/dev/null | cut -f1)"
    echo "  ROMs (${roms_size}) are NOT in this archive. Either copy them separately"
    echo "  or re-run with --with-content."
    echo
fi
