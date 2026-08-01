#!/bin/bash
# ---------------------------------------------------------------------------
# 20-kodi-addons - the streaming add-ons and the Kodi-side shell launcher.
#
# Kodi installs add-ons from zip files, so this module copies the bundled
# repository zips somewhere Kodi's file browser can reach and prints the exact
# clicks needed. Repositories are preferred over one-off zips because they
# keep the add-ons updated afterwards.
#
# It also installs the Shell Script Launcher menu, which is what puts the VPN
# controls inside Kodi.
#
# See docs/20-kodi-addons.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

# Where Kodi's "Install from zip file" browser will look.
ADDON_DROP="$HOME/kodi-addons-to-install"

step "Staging the bundled add-on packages"
mkdir -p "$ADDON_DROP"
found=0
while IFS= read -r -d '' zip; do
    cp -n "$zip" "$ADDON_DROP/" && found=$((found + 1))
done < <(find "$REC_ASSETS/plugins" -name '*.zip' -print0)
ok "Staged $found package(s) in $ADDON_DROP"

step "Allowing installation from unknown sources"
# Every add-on below lives outside the official Kodi repository, so Kodi will
# refuse to install them until this is switched on. It cannot be set from
# outside a running Kodi, so this is a reminder rather than an action.
note "Kodi > Settings > System > Add-ons > Unknown sources -> ON"

step "Installing the Shell Script Launcher menu"
# This file defines the entries that appear inside Kodi. It lives in the repo
# so it stays version-controlled, and is symlinked to the path the add-on
# expects, so edits take effect without copying anything.
MENU_SRC="$REC_ASSETS/kodi/shell_command_launcher.menu"
MENU_DST="$HOME/shell_command_launcher.menu"

# Rewrite the bundled menu so its commands point at wherever this repository
# actually lives, rather than assuming the home directory.
sed "s|@REC_BIN@|$REC_BIN|g" "$MENU_SRC" > "$MENU_DST"
ok "Wrote $MENU_DST"

echo
ok "Add-on packages staged."
cat <<EOF

${REC_C_BOLD}Install the add-ons from inside Kodi${REC_C_OFF}

First, once:
  Settings > System > Add-ons > Unknown sources -> ON

Then for each package, use:
  Settings > Add-ons > Install from zip file > Home folder > kodi-addons-to-install

${REC_C_BOLD}repository.linuxaddons-1.0.1.zip${REC_C_OFF}  - Shell Script Launcher
    After installing the repository:
      Install from repository > Linux Add-on Repository > Program add-ons
        > Shell Script Launcher
    Configure it to read: $MENU_DST
    Then put it on the home screen: right-click > Add to Favourites.
    This is what gives you VPN control without leaving Kodi.

${REC_C_BOLD}repository.mtr81.zip${REC_C_OFF}             - Polish TVP VOD, Polsat, Player.pl
    Install from repository > mtr81 repo > Video add-ons

${REC_C_BOLD}plugin.video.yleareena.jade.zip${REC_C_OFF}  - Finnish Yle Areena
    Most content is geo-restricted; connect the VPN first:
      bash $REC_BIN/nordvpn_connect.sh fi

${REC_C_BOLD}Not bundled - download these yourself${REC_C_OFF}

  YouTube   https://github.com/anxdpanic/plugin.video.youtube/releases
            Pinning a copy here would be stale more often than not: the
            add-on is re-released whenever YouTube changes something.
            It also needs your own Google API key - see docs/20-kodi-addons.md.
            Download the .zip into $ADDON_DROP and install it like the others.
            Once your API key is in, run:
                bash $REC_BIN/kodi_youtube_fix.sh
            or a mix shared from the phone hangs Kodi and drains the quota.

  Netflix, Disney+ and other DRM services additionally need Widevine and an
  authentication key - documented in docs/20-kodi-addons.md.

  Netflix logins currently fail with a 404 on .../api/shakti/mre/profilehub -
  Netflix retired that endpoint. After installing the add-on, run:
      bash $REC_BIN/kodi_netflix_fix.sh
  and re-run it after each add-on update. See docs/20-kodi-addons.md.
EOF
