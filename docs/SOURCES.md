# Sources and credits

This project is mostly glue. The hard parts were worked out by other people,
and this page keeps their tutorials findable — both to credit them and because
when something breaks, the original write-up is usually where the answer is.

Each entry says which module it relates to, so you can go from a symptom to
the source that explains it.

---

## Bluetooth (the Pi as a speaker)

- [Bluetooth audio on the Raspberry Pi](https://howchoo.com/pi/bluetooth-raspberry-pi)
  — pairing and the bluez side.
- [Bluetooth assigned numbers](https://www.bluetooth.com/specifications/assigned-numbers/)
  — where the `0x200414` audio device class comes from.
- [How can I make PulseAudio run as root?](https://stackoverflow.com/questions/66775654/how-can-i-make-pulseaudio-run-as-root)
  — the missing piece: keeping it working under **Kodi and the console**,
  which have no login session and so no per-user PulseAudio.
- [PulseAudio: what is wrong with system mode](https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/WhatIsWrongWithSystemWide/)
  — upstream's own view of the trade-off. Worth reading before enabling it.

→ [docs/85-bluetooth.md](85-bluetooth.md)

## Kodi

- [Kodi](https://kodi.tv/) — the project itself.
- [PVR IPTV Simple Client](https://kodi.tv/addons/omega/pvr.iptvsimple/) — the
  live TV/radio add-on.
- [Setting up PVR IPTV Simple Client](https://www.firesticktricks.com/pvr-iptv-simple-client-on-kodi.html)
  — step-by-step with screenshots; useful if the summary in our docs is too terse.
- [Installing the YouTube add-on](https://www.firesticktricks.com/youtube-kodi-addon.html)
  — including the Google API key setup, which is the fiddly part.
- [List of Kodi built-in functions](https://kodi.wiki/view/List_of_built-in_functions)
  — everything `kodi-send -a ...` can do, used by the GPIO buttons.

→ [docs/10-kodi.md](10-kodi.md), [docs/15-kodi-iptv.md](15-kodi-iptv.md), [docs/20-kodi-addons.md](20-kodi-addons.md)

## IPTV channel lists

- [iptv-org](https://github.com/iptv-org/iptv) — the largest public collection.
  - [Polish channels (M3U)](https://iptv-org.github.io/iptv/languages/pol.m3u)
  - [Polish streams, raw file](https://raw.githubusercontent.com/iptv-org/iptv/refs/heads/master/streams/pl.m3u)
- [fmstream.org](https://fmstream.org/index.php) — radio stations worldwide;
  copy a stream URL straight into a playlist.

→ [docs/15-kodi-iptv.md](15-kodi-iptv.md)

## Kodi add-ons

- [Linux Add-on Repository](https://github.com/wastis/LinuxAddonRepo) — source
  of **Shell Script Launcher**, which is what puts VPN and UI controls inside
  Kodi.
- [mtr81 Kodi add-ons](https://mtr81.github.io/kodi_addons/) — Polish TVP VOD,
  Polsat Box Go, Player.pl.
- [YouTube add-on releases](https://github.com/anxdpanic/plugin.video.youtube/releases)
- [Yle Areena add-on](https://github.com/aajanki/plugin.video.yleareena.jade)
  — Finnish public broadcaster.
  - [Setup thread](https://www.huoltovalikko.com/threads/kodi-yle-areena-2022.15190/)
- [Netflix add-on](https://github.com/CastagnaIT/plugin.video.netflix)
  - [Logging in with an authentication key](https://github.com/CastagnaIT/plugin.video.netflix/wiki/Login-with-Authentication-key)
    — the recommended route, since Netflix blocks logins from unusual devices.

→ [docs/20-kodi-addons.md](20-kodi-addons.md)

## RetroPie

- [RetroPie-Setup](https://github.com/RetroPie/RetroPie-Setup) — the installer.
- [How to cleanly stop EmulationStation from the command line](https://retropie.org.uk/forum/topic/22266/how-to-cleanly-stop-emulationstation-from-the-command-line/3)
  — why the UI switcher uses `pkill` rather than a graceful quit.

→ [docs/30-retropie.md](30-retropie.md)

## Desktop remote control

- [KDE Connect](https://kdeconnect.kde.org/) — phone as touchpad, keyboard and
  clipboard for the desktop.
- [Kore](https://kodi.tv/addons/omega/plugin.program.kore/) — Kodi's official
  phone remote.

→ [docs/45-kdeconnect.md](45-kdeconnect.md), [docs/10-kodi.md](10-kodi.md)

## NordVPN

- [NordVPN on Raspberry Pi](https://nordvpn.com/download/raspberry-pi/) — the
  vendor's install page.
- [Access tokens](https://my.nordaccount.com/dashboard/nordvpn/) — generate the
  token that goes in `config.sh`.

→ [docs/70-nordvpn.md](70-nordvpn.md)

## Port forwarding

- [IP Webcam (Android)](https://play.google.com/store/apps/details?id=com.pas.webcam)
  — turns an old phone into a camera; the original reason this module exists.

→ [docs/75-port-forwarding.md](75-port-forwarding.md)

## Web server

- [No-IP Dynamic Update Client](https://my.noip.com/dynamic-dns/duc) — note
  that No-IP's own installer does **not** work on Raspberry Pi OS; module
  `80-webserver` builds it from source instead.
- [Certbot](https://certbot.eff.org/) — Let's Encrypt certificates for Apache.

→ [docs/80-webserver.md](80-webserver.md)

## Weather

- [OpenWeatherMap API](https://openweathermap.org/api) — free tier, needs a key.
- [ip-api.com](http://ip-api.com/) — IP geolocation for `REC_WEATHER_LOCATION="auto"`,
  no key required.

→ [docs/95-weather.md](95-weather.md)

---

## Where these came from

Most of these links were originally collected in a loose `INSTALL_LOG.txt` in
the home directory, alongside a handful of one-line reminders. That file is
gone; its contents now live in the module they belong to, and every link it
carried is listed above.

If you add something to this project, add its source here too — a working
setup whose provenance has been lost is very hard to fix a year later.
