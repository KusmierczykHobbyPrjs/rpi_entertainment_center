#!/bin/bash
# ---------------------------------------------------------------------------
# kodi_youtube_fix.sh - make a shared YouTube "Mix" playable.
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
#   A mix is endless radio, not a playlist. YouTube does not store it; it
#   re-generates a rolling ~50-track window on every request, so
#   playlistItems.list never stops handing out a nextPageToken. Measured on
#   RDdQw4w9WgXcQ against the live API:
#
#     page 1: 50 items          page 3: 49 items, 48 of them already seen
#     page 2: 49 items,         page 4: 49 items, and its token is page 2's
#             48 of them                 - the tokens cycle from here for ever
#             already seen
#
#     4 pages = 197 queue entries, 53 distinct videos. Page 2 is page 1 served
#     again from the top: the first ten video IDs are identical.
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
# THE FIX - three edits, because stopping the loop is not enough on its own
#   1. resource_manager.py: stop paging when a page token comes round for the
#      second time. A well-formed playlist never repeats one, so finite
#      playlists page to the end exactly as before, and a mix stops after four
#      pages. Both paging loops are patched - the cache pass spins the same way
#      once the pages are cached, without even the network to slow it down.
#
#      Deliberately not a page-count cap: real uploads playlists run to
#      thousands of videos and a cap would silently truncate them.
#
#   2. yt_play.py: with the loop stopped you would queue those 197 entries -
#      the same 50 songs four times over, in the same order. So when a mix is
#      among the requested playlists, drop videos already in the queue. You get
#      the ~53 distinct tracks once, in order.
#
#      Scoped to RD... ids on purpose. A hand-made playlist may repeat a track
#      deliberately, and that is none of our business.
#
#   3. yt_play.py again: hand Kodi a command, not a file, so the queue is not
#      thrown away. Kore shares by calling JSON-RPC Player.Open on
#      plugin://.../play/?playlist_id=..., and Kodi treats that as ONE playable
#      file. Measured in kodi.log: the add-on fills the playlist, then
#
#        Playlist.OnAdd x12  playlistid 1     <- the queue
#        Playlist.OnClear    playlistid 1     <- Kodi throws it away
#        Playlist.OnAdd x1   playlistid 1     <- replaced by the resolved track
#
#      and one song plays. Which playlist gets filled is decided by
#      get_playlist_id(), which asks whatever is playing at that moment - so
#      the queue sometimes lands in the MUSIC playlist instead and survives
#      there, unused. Both outcomes play one track.
#
#      So on the resolve path we now return command://Playlist.PlayOffset(...)
#      instead of a media item. The add-on runs it as a post-run action and
#      starts its own playlist; Kodi has no file to play, so it never clears
#      anything. This is the add-on's own mechanism - it already uses exactly
#      this for busy-dialog recovery.
#
#      Verified on the Pi against a real Player.Open: 'Builtin command queued:
#      Playlist.PlayOffset(video,0)', no OnClear, 10 items left in the queue,
#      and Player.GoTo(next) advanced 0 -> 1 with the queue intact. A normal
#      PL... playlist opened the same way also kept its 14 items, so this
#      helps every shared playlist, not just mixes.
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
HELPERS="$ADDON_DIR/resources/lib/youtube_plugin/youtube/helper"
TARGETS=("$HELPERS/resource_manager.py" "$HELPERS/yt_play.py")
MARKER="rec-patch:endless-mix"
# Bumped whenever the edits below change. An add-on already carrying an older
# revision has to be restored and re-patched - the edits are anchored on stock
# 7.4.4 source and cannot be stacked on top of each other.
REVISION=3
STAMP="$ADDON_DIR/.rec-youtube-patch"

mode="apply"
case "${1:-}" in
    --status)  mode="status" ;;
    --revert)  mode="revert" ;;
    --help|-h) sed -n '2,95p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "")        ;;
    *)         rec_die "Unknown option: $1  (try --help)" ;;
esac

for target in "${TARGETS[@]}"; do
    [[ -f "$target" ]] || rec_die "YouTube add-on not found at $ADDON_DIR
Install it first - see docs/20-kodi-addons.md."
done

version="$(sed -n 's/.*id="plugin.video.youtube".*version="\([^"]*\)".*/\1/p' \
    "$ADDON_DIR/addon.xml" 2>/dev/null | head -1)"
[[ -n "$version" ]] || version="unknown"

# Both files carry the marker, so a half-applied state is visible rather than
# silently passing for a whole one.
marked() {
    local target
    for target in "${TARGETS[@]}"; do
        grep -q "$MARKER" "$target" 2>/dev/null || return 1
    done
    return 0
}

stamp_read() { [[ -f "$STAMP" ]] && cat "$STAMP" 2>/dev/null; }

applied() { marked && [[ "$(stamp_read)" == "$REVISION" ]]; }

# -- status ----------------------------------------------------------------
if [[ "$mode" == "status" ]]; then
    rec_log "YouTube add-on version: $version"
    for target in "${TARGETS[@]}"; do
        if grep -q "$MARKER" "$target" 2>/dev/null; then
            rec_log "  [x] $(basename "$target")"
        else
            rec_log "  [ ] $(basename "$target")"
        fi
    done
    if applied; then
        rec_log "Revision $REVISION. A shared mix pages, de-duplicates and plays through."
    elif marked; then
        rec_log "Revision $(stamp_read || echo 'unrecorded') - OUT OF DATE (current: $REVISION)."
        rec_log "Only the first track of a shared mix will play. Re-run to upgrade:"
        rec_log "  bash bin/kodi_youtube_fix.sh"
    else
        rec_log "A shared mix will hang Kodi and burn your daily API quota."
        rec_log "  bash bin/kodi_youtube_fix.sh"
    fi
    exit 0
fi

# -- revert ----------------------------------------------------------------
if [[ "$mode" == "revert" ]]; then
    restored=0
    for target in "${TARGETS[@]}"; do
        [[ -f "$target.rec-orig" ]] || continue
        cp -- "$target.rec-orig" "$target" || rec_die "Could not restore $target"
        rm -f -- "$target.rec-orig"
        restored=$((restored + 1))
    done
    rm -f -- "$STAMP"
    if (( restored )); then
        rec_log "Restored $restored file(s) as shipped. Restart Kodi."
    else
        rec_log "Nothing to revert - no backups in $HELPERS"
    fi
    exit 0
fi

# -- apply -----------------------------------------------------------------
if applied; then
    rec_log "Endless-mix patch: already applied, revision $REVISION (add-on $version)."
    exit 0
fi

# An older revision is in place. The edits anchor on stock 7.4.4 source, so
# they cannot be stacked - restore first, then apply the current set.
if marked; then
    rec_log "Upgrading from revision $(stamp_read || echo 'unrecorded') to $REVISION."
    for target in "${TARGETS[@]}"; do
        [[ -f "$target.rec-orig" ]] || rec_die \
            "$target is patched but has no backup - reinstall the add-on first."
    done
    for target in "${TARGETS[@]}"; do
        cp -- "$target.rec-orig" "$target" || rec_die "Could not restore $target"
    done
fi

# Back up before touching anything, and remember which backups are ours, so a
# refusal below leaves no misleading .rec-orig for --revert to find later.
ours=()
for target in "${TARGETS[@]}"; do
    [[ -f "$target.rec-orig" ]] && continue
    cp -- "$target" "$target.rec-orig" || rec_die "Could not back up $target"
    ours+=("$target.rec-orig")
done

undo() {
    for target in "${TARGETS[@]}"; do
        [[ -f "$target.rec-orig" ]] && cp -- "$target.rec-orig" "$target"
    done
    (( ${#ours[@]} )) && rm -f -- "${ours[@]}"
    rec_error "Patch not applied; the add-on is left untouched."
    rec_error "Its source has changed - check whether upstream has fixed this:"
    rec_die   "  https://github.com/anxdpanic/plugin.video.youtube"
}

python3 - "$MARKER" "${TARGETS[@]}" <<'PYEOF'
import sys

marker, rm_path, play_path = sys.argv[1], sys.argv[2], sys.argv[3]

# Every block below is quoted exactly as 7.4.4 ships it. Matching whole blocks
# rather than a regex means an upstream rewrite of this area is a clean
# refusal, not a mangled add-on.
EDITS = {
    rm_path: (
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
    ),
    play_path: (
        (
            """        if not video_items:
            return False, None

        result = process_items_for_playlist(context, video_items, action=action)
""",
            """        if playlist_ids and any(playlist_id.startswith('RD')
                                for playlist_id in playlist_ids):
            # %s - applied by rpi_entertainment_center.
            # YouTube re-generates a mix on every request rather than storing
            # it, so consecutive pages are the same rolling window served from
            # the top - four pages of RDdQw4w9WgXcQ are 197 entries but only 53
            # distinct videos. Queue each of them once.
            #
            # Scoped to mixes: a hand-made playlist may repeat a track
            # deliberately, and that is none of our business.
            seen_ids = set()
            unique_items = []
            for video_item in video_items:
                video_id = video_item.video_id
                if video_id and video_id in seen_ids:
                    continue
                seen_ids.add(video_id)
                unique_items.append(video_item)
            if len(unique_items) != len(video_items):
                logging.debug('Mix: queued {0} distinct of {1} items'
                              .format(len(unique_items), len(video_items)))
                video_items = unique_items

        if not video_items:
            return False, None

        # %s - applied by rpi_entertainment_center.
        # Kore shares by calling Player.Open on this URL, and Kodi treats it as
        # one playable file: it clears the playlist we just built and plays the
        # single track we resolve for it. Ask for a command instead - see
        # process_items_for_playlist below.
        result = process_items_for_playlist(
            context,
            video_items,
            action=(action if action or context.get_handle() == -1
                    else 'resolve_playlist'),
        )
""" % (marker, marker),
        ),
        (
            """    if action == 'queue':
        return items
""",
            """    if action == 'resolve_playlist':
        # %s - applied by rpi_entertainment_center.
        # Hand Kodi a builtin rather than a file. The add-on runs it as a
        # post-run action and starts its own playlist, so Kodi has nothing to
        # play and never clears the queue. Same mechanism the add-on already
        # uses to recover from a stuck busy dialog.
        command = playlist_player.play_playlist_item(position, defer=True)
        if command:
            return UriItem(command)
    if action == 'queue':
        return items
""" % marker,
        ),
    ),
}

for path, edits in EDITS.items():
    with open(path, encoding='utf-8') as fh:
        src = fh.read()

    for index, (old, new) in enumerate(edits, start=1):
        count = src.count(old)
        if count != 1:
            sys.exit('%s edit %d: expected this block exactly once, found %d'
                     % (path, index, count))
        src = src.replace(old, new)

    # Refuse to write a file Kodi cannot import.
    try:
        compile(src, path, 'exec')
    except SyntaxError as exc:
        sys.exit('%s: patched source does not compile: %s' % (path, exc))

    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(src)
PYEOF

(( $? == 0 )) || undo

printf '%s\n' "$REVISION" > "$STAMP"

# An add-on update that restores the .py files would otherwise leave our
# bytecode cached beside them.
rm -rf -- "$HELPERS/__pycache__"

rec_log "Endless-mix patch revision $REVISION applied to add-on $version."
rec_log ""
rec_log "Restart Kodi, then share a mix from the phone. It should start within a"
rec_log "couple of seconds and play through the queue rather than stopping after"
rec_log "the first track."
rec_log ""
rec_log "Revert with: bash bin/kodi_youtube_fix.sh --revert"
