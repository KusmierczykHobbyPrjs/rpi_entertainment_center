# YouTube add-on

**Deliberately not bundled.** This add-on breaks and gets re-released whenever
YouTube changes something, so a copy pinned here would be stale more often
than not.

Download the current release into `~/kodi-addons-to-install/` on the Pi:

    https://github.com/anxdpanic/plugin.video.youtube/releases

Then install it from inside Kodi:

    Settings > Add-ons > Install from zip file > Home folder
      > kodi-addons-to-install

Keeping the previous release alongside the current one is worth doing — when
an update breaks playback, rolling back is the quickest fix.

## It needs your own Google API key

The add-on's shared keys are routinely exhausted, which shows up as "quota
exceeded" or an empty home screen. See `docs/20-kodi-addons.md` for how to
create an API key, an OAuth client ID and a client secret in the Google Cloud
Console.

Keep those credentials in the add-on's own settings, never in this repository.

## And then run the mix fix

With a personal key, sharing a generated "Mix — Artist — Title" from the phone
hangs Kodi on "Updating playlist… 0/0" and drains the whole day's quota within
minutes. Not fixed upstream:

    bash bin/kodi_youtube_fix.sh

Re-run it after every add-on update. See `docs/20-kodi-addons.md`.
