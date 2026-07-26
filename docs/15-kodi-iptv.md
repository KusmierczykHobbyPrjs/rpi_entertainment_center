# 15-kodi-iptv — live TV and radio

Turns Kodi into a TV and radio tuner using public internet streams. No tuner
hardware, no subscription, no aerial.

```bash
./install.sh 15-kodi-iptv
```

**Prerequisites:** `00-base`, `10-kodi`.

---

## What it does

1. Installs `kodi-pvr-iptvsimple`, the PVR IPTV Simple Client.
2. Copies the bundled playlists to `~/.local/share/rec-iptv/`.
3. Optionally runs the stream checker to find dead channels.

The playlists live outside `~/.kodi` deliberately: a Kodi reinstall does not
wipe them, and you can edit them over SSH without hunting through add-on data
directories. If you have already edited a playlist, the installer will not
overwrite it — the bundled version is saved alongside as `<name>.new`.

---

## Finish the setup inside Kodi

The add-on cannot be configured from outside a running Kodi.

> Settings → Add-ons → My add-ons → PVR clients → **PVR IPTV Simple Client** →
> Configure

**General tab**

| Setting | Value |
|---|---|
| Location | Local path |
| M3U play list path | `/home/pi/.local/share/rec-iptv/iptvsimple_playlist_pl.m3u` |

**Advanced tab**

| Setting | Value |
|---|---|
| User agent | `Mozilla/5.0` |

**Set the user agent.** Many public streams reject Kodi's default with a 403,
which shows up as channels that simply refuse to play with no useful error.
`VLC` works as an alternative if `Mozilla/5.0` does not.

Then **enable** the add-on and restart Kodi. **TV** and **Radio** appear on
the home screen.

Screenshots: [`photos/iptv/`](../photos/iptv/).

---

## The bundled playlists

In `assets/iptv/`, installed to `~/.local/share/rec-iptv/`:

| File | Contents |
|---|---|
| `iptvsimple_playlist_pl.m3u` | The main curated list — Polish radio stations plus a selection of TV channels. |
| `iptvsimple_channels_pl0.m3u` | Additional Polish channels. |
| `iptvsimple_channels_pl1.m3u` | Additional Polish channels. |
| `iptvsimple_channels_pl2.m3u` | Additional Polish channels. |

Public streams disappear regularly. Treat these as a starting point, not a
fixed channel line-up.

---

## Finding more channels

| Source | Notes |
|---|---|
| [iptv-org](https://github.com/iptv-org/iptv) | The largest public collection, organised by country and language. |
| [iptv-org Polish list](https://iptv-org.github.io/iptv/languages/pol.m3u) | Direct M3U. |
| [fmstream.org](https://fmstream.org/) | Radio stations worldwide; copy the stream URL into your playlist. |

Point Kodi at a remote list directly by setting Location to **Remote path
(internet address)** and pasting a URL. Convenient, but you get whatever that
list contains, including channels you do not want.

---

## Playlist format

An M3U entry looks like this:

```
#EXTINF:-1 tvg-id="channel.pl" tvg-logo="https://example.com/logo.png" group-title="Radio",Station Name
http://stream.example.com/live.mp3
```

| Field | Purpose |
|---|---|
| `tvg-id` | Matches the channel to an EPG guide entry. |
| `tvg-logo` | Channel icon URL. |
| `group-title` | Kodi groups channels by this — e.g. `Radio`, `News`, `Sport`. |
| after the comma | The channel name shown in Kodi. |
| next line | The stream URL. |

Add a station by appending two lines. Radio streams are usually a plain MP3 or
AAC URL.

---

## Checking for dead streams

Public streams go offline constantly. The bundled checker tests every entry
and reports which ones no longer respond:

```bash
python3 bin/iptv_streams_checker.py ~/.local/share/rec-iptv/iptvsimple_playlist_pl.m3u
```

This takes a few minutes for a long list — it opens each stream in turn.

---

## Verify

```bash
./bin/doctor.sh kodi
```

Should report the IPTV client installed and the playlists present.

---

## Troubleshooting

**No TV or Radio section on the home screen**

- The add-on must be **enabled**, not just installed.
- Restart Kodi — the PVR manager only loads at startup.
- Check the playlist path is correct and the file is readable.

**Channels are listed but none play**

- Set the user agent to `Mozilla/5.0` (Advanced tab). This is the most common
  cause.
- Test the URL directly on another machine:
  `ffplay "<stream-url>"` or paste it into VLC.
- Try the stream checker to see how many are dead — public lists rot fast.

**Some channels are geo-blocked**

Use the VPN to appear in the right country (module `70-nordvpn`):

```bash
bash bin/nordvpn_connect.sh pl
```

**Buffering**

- Wired Ethernet is significantly more reliable than Wi-Fi for streaming.
- Increase Kodi's cache: create `~/.kodi/userdata/advancedsettings.xml` with

  ```xml
  <advancedsettings>
    <cache>
      <buffermode>1</buffermode>
      <memorysize>78643200</memorysize>
    </cache>
  </advancedsettings>
  ```

  That is 75 MB of buffer. Do not go much higher on a 1 GB Pi 3B.

**Empty programme guide**

The bundled playlists carry no EPG data. Add an XMLTV source in the add-on's
**EPG settings** — iptv-org publishes guides matching its channel lists.
