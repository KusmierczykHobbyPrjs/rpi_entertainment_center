#!/bin/bash
# ---------------------------------------------------------------------------
# 15-kodi-iptv - live TV and radio from public IPTV streams.
#
# Installs the PVR IPTV Simple Client and copies the bundled playlists into
# place. The client turns an .m3u playlist into Kodi's normal TV/Radio
# sections, complete with channel numbers and a remote-friendly guide.
#
# See docs/15-kodi-iptv.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

step "Installing the PVR IPTV Simple Client"
apt_install kodi-pvr-iptvsimple || exit 1

step "Installing the bundled playlists"
# Kept outside ~/.kodi so that a Kodi reinstall does not wipe them, and so
# they can be edited over SSH without hunting through the add-on data folder.
PLAYLIST_DIR="$HOME/.local/share/rec-iptv"
mkdir -p "$PLAYLIST_DIR"

for playlist in "$REC_ASSETS"/iptv/*.m3u; do
    [[ -f "$playlist" ]] || continue
    name="$(basename "$playlist")"
    if [[ -f "$PLAYLIST_DIR/$name" ]] && ! cmp -s "$playlist" "$PLAYLIST_DIR/$name"; then
        # Never silently overwrite a playlist the user has edited.
        cp "$playlist" "$PLAYLIST_DIR/${name}.new"
        skip "$name differs from yours - bundled copy saved as ${name}.new"
    else
        cp "$playlist" "$PLAYLIST_DIR/$name"
        ok "Installed $name"
    fi
done

note "Playlists live in: $PLAYLIST_DIR"

step "Checking the bundled Polish playlist for dead streams (optional)"
if confirm "Test the streams now? This takes a few minutes."; then
    python3 "$REC_BIN/iptv_streams_checker.py" \
        "$PLAYLIST_DIR/iptvsimple_playlist_pl.m3u" || \
        skip "Stream check reported problems - see the output above"
else
    skip "Skipped. Run it later with:"
    note "  python3 $REC_BIN/iptv_streams_checker.py $PLAYLIST_DIR/iptvsimple_playlist_pl.m3u"
fi

echo
ok "IPTV client installed."
cat <<EOF

${REC_C_BOLD}Finish the setup inside Kodi${REC_C_OFF} (the add-on cannot be configured from
outside a running Kodi):

  1. Settings > Add-ons > My add-ons > PVR clients > PVR IPTV Simple Client
  2. Configure > General:
       Location            : Local path
       M3U play list path  : $PLAYLIST_DIR/iptvsimple_playlist_pl.m3u
  3. Configure > Advanced:
       User agent          : Mozilla/5.0
       (many public streams reject Kodi's default user agent with a 403)
  4. Enable the add-on, then restart Kodi.
  5. "TV" and "Radio" appear on the home screen.

See docs/15-kodi-iptv.md for where to find more channel lists.
EOF
