#!/bin/bash
# ---------------------------------------------------------------------------
# kodi_youtube_fix.sh - stop a YouTube "Mix" from looping forever.
#
# THE BUG
#   Share a generated mix from the phone app - the ones called
#   "Mix - Artist - Title", whose URL carries &list=RD... - to Kore, and Kodi
#   sits on "Updating playlist... 0%, 0/0" for ever. Nothing plays, the
#   YouTube Data API quota is gone within minutes, and anything else that asks
#   the player to do something (kodi-send, the GPIO buttons, Kore itself)
#   queues up behind a plugin call that never returns.
#
# WHY
#   A mix is endless radio, not a playlist. YouTube generates it as you go, so
#   playlistItems.list never stops handing out a nextPageToken - measured on
#   RDdQw4w9WgXcQ, the token settles into a two-value cycle from page 2
#   onwards and repeats for ever:
#
#     page 1: items=50 next='EAAaFVBUOkVndFFRWHBJTFZsQmJFWlpZdw'
#     page 2: items=49 next='EAAaFVBUOkVndG9RM1ZOVjNKbVdFYzBSUQ'
#     page 3: items=49 next='EAAaFVBUOkVnc3pSM2RxWmxWR2VWazJUUQ'
#     page 4: items=49 next='EAAaFVBUOkVndG9RM1ZOVjNKbVdFYzBSUQ'   <- page 2's
#     page 5: items=49 next='EAAaFVBUOkVnc3pSM2RxWmxWR2VWazJUUQ'   <- page 3's
#
#   get_playlist_items() in resource_manager.py pages with "while 1:" and only
#   stops when a page comes back without a token. For a mix that never
#   happens, so it fetches for ever, one quota unit per request. The progress
#   dialog reads 0/0 because the total is only known once the fetch finishes.
#
#   This bites you specifically because you configured your own API key. With
#   the add-on's shared keys v3_api_available() is false and the add-on takes
#   the InnerTube path instead, which is not affected.
#
# THE FIX
#   Stop paging when a page token comes round for the second time. A
#   well-formed playlist never repeats one, so finite playlists page to the end
#   exactly as before; a mix stops after three pages with ~148 videos in the
#   queue, which is more radio than anyone listens to in a sitting. Both paging
#   loops are patched - the cache pass spins the same way once the pages are
#   cached, without even the network to slow it down.
#
#   Deliberately not a page-count cap: real uploads playlists run to thousands
#   of videos and a cap would silently truncate them.
#
# UPSTREAM
#   Present in 7.4.4 (the current release) and unchanged on master. No issue
#   filed as of August 2026, so there is nothing to update to yet.
#   https://github.com/anxdpanic/plugin.video.youtube
#
# USAGE
#   bash bin/kodi_youtube_fix.sh              apply
#   bash bin/kodi_youtube_fix.sh --status     report what is applied
#   bash bin/kodi_youtube_fix.sh --revert     restore the add-on as shipped
#
# Restart Kodi afterwards. Re-run after every add-on update - an update
# overwrites the patch, which is the outcome you want, since a genuine
# upstream fix should win. ./bin/doctor.sh kodi tells you when that has
# happened.
#
# See docs/20-kodi-addons.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ADDON_DIR="${KODI_HOME:-$HOME/.kodi}/addons/plugin.video.youtube"
TARGET="$ADDON_DIR/resources/lib/youtube_plugin/youtube/helper/resource_manager.py"
BACKUP="$TARGET.rec-orig"
MARKER="rec-patch:endless-mix"

mode="apply"
case "${1:-}" in
    --status)  mode="status" ;;
    --revert)  mode="revert" ;;
    --help|-h) sed -n '2,61p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "")        ;;
    *)         rec_die "Unknown option: $1  (try --help)" ;;
esac

[[ -f "$TARGET" ]] || rec_die "YouTube add-on not found at $ADDON_DIR
Install it first - see docs/20-kodi-addons.md."

version="$(sed -n 's/.*id="plugin.video.youtube".*version="\([^"]*\)".*/\1/p' \
    "$ADDON_DIR/addon.xml" 2>/dev/null | head -1)"
[[ -n "$version" ]] || version="unknown"

applied() { grep -q "$MARKER" "$TARGET" 2>/dev/null; }

# -- status ----------------------------------------------------------------
if [[ "$mode" == "status" ]]; then
    rec_log "YouTube add-on version: $version"
    if applied; then
        rec_log "  [x] Endless-mix patch - shared mixes stop paging and play"
    else
        rec_log "  [ ] Endless-mix patch - a shared mix will hang and burn your quota"
        rec_log "      bash bin/kodi_youtube_fix.sh"
    fi
    exit 0
fi

# -- revert ----------------------------------------------------------------
if [[ "$mode" == "revert" ]]; then
    if [[ -f "$BACKUP" ]]; then
        cp -- "$BACKUP" "$TARGET" || rec_die "Could not restore $TARGET"
        rm -f -- "$BACKUP"
        rec_log "Restored the add-on as shipped. Restart Kodi."
    else
        rec_log "Nothing to revert - no backup at $BACKUP"
    fi
    exit 0
fi

# -- apply -----------------------------------------------------------------
if applied; then
    rec_log "Endless-mix patch: already applied (add-on $version)."
    exit 0
fi

backup_is_ours=0
if [[ ! -f "$BACKUP" ]]; then
    cp -- "$TARGET" "$BACKUP" || rec_die "Could not back up $TARGET"
    backup_is_ours=1
fi

python3 - "$TARGET" "$MARKER" <<'PYEOF'
import sys

path, marker = sys.argv[1], sys.argv[2]

# Both paging loops, quoted exactly as 7.4.4 ships them. Matching whole blocks
# rather than a regex means an upstream rewrite of this area is a clean
# refusal, not a mangled add-on.
EDITS = (
    # The cache pass. Once a mix's pages are cached this spins without any
    # network at all, appending to batch_ids until memory runs out.
    (
        """        for playlist_id in ids:
            page_token = page_token or 0
            while 1:
                batch_id = (playlist_id, page_token)
                batch_ids.append(batch_id)
""",
        """        for playlist_id in ids:
            page_token = page_token or 0
            # %s - applied by rpi_entertainment_center.
            # A mix (RD...) is endless radio: its nextPageToken cycles instead
            # of ever running out, so this loop never ends. A well-formed
            # playlist never repeats a page token, so remembering them costs
            # finite playlists nothing.
            seen_tokens = {page_token}
            while 1:
                batch_id = (playlist_id, page_token)
                batch_ids.append(batch_id)
""" % marker,
    ),
    (
        """                page_token = batch.get('nextPageToken') if fetch_next else None
                if not page_token:
                    break

        if result:
""",
        """                page_token = batch.get('nextPageToken') if fetch_next else None
                if not page_token or page_token in seen_tokens:
                    break
                seen_tokens.add(page_token)

        if result:
""",
    ),
    # The fetch pass - the one that burns a quota unit per lap.
    (
        """        for playlist_id, page_token in to_update:
            new_batch_ids = []
            batch_id = (playlist_id, page_token)
            insert_point = batch_ids.index(batch_id, insert_point)
            while 1:
""",
        """        for playlist_id, page_token in to_update:
            new_batch_ids = []
            batch_id = (playlist_id, page_token)
            insert_point = batch_ids.index(batch_id, insert_point)
            seen_tokens = {page_token}
            while 1:
""",
    ),
    (
        """                page_token = batch.get('nextPageToken') if fetch_next else None
                if not page_token:
                    break

            if new_batch_ids:
""",
        """                page_token = batch.get('nextPageToken') if fetch_next else None
                if not page_token or page_token in seen_tokens:
                    break
                seen_tokens.add(page_token)

            if new_batch_ids:
""",
    ),
)

with open(path, encoding='utf-8') as fh:
    src = fh.read()

for index, (old, new) in enumerate(EDITS, start=1):
    count = src.count(old)
    if count != 1:
        sys.exit('edit %d: expected this block exactly once, found %d'
                 % (index, count))
    src = src.replace(old, new)

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src)

# Refuse to leave a file Kodi cannot import.
try:
    compile(src, path, 'exec')
except SyntaxError as exc:
    sys.exit('patched file does not compile: %s' % exc)
PYEOF

if (( $? != 0 )); then
    # Nothing was written - the python above replaces in memory and only saves
    # once every edit has matched. Restoring anyway costs nothing, and a backup
    # we took of a file we then refused to patch would only mislead --revert.
    cp -- "$BACKUP" "$TARGET"
    (( backup_is_ours )) && rm -f -- "$BACKUP"
    rec_error "Patch not applied; $TARGET left untouched."
    rec_error "The add-on source has changed - check whether upstream has fixed this:"
    rec_die   "  https://github.com/anxdpanic/plugin.video.youtube"
fi

# A stale .pyc next to a patched .py is not a risk Kodi's importer takes, but
# an add-on update that restores the .py would leave ours cached. Cheap to be
# sure.
rm -rf -- "$(dirname "$TARGET")/__pycache__"

rec_log "Endless-mix patch applied to add-on $version."
rec_log ""
rec_log "Restart Kodi, then share a mix from the phone again - it should start"
rec_log "playing within a couple of seconds with ~148 tracks queued."
rec_log ""
rec_log "Revert with: bash bin/kodi_youtube_fix.sh --revert"
