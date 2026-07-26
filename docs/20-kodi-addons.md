# 20-kodi-addons — streaming add-ons and the shell launcher

Stages the bundled Kodi add-on packages and installs the menu that puts VPN
and UI controls inside Kodi.

```bash
./install.sh 20-kodi-addons
```

**Prerequisites:** `00-base`, `10-kodi`.

---

## What it does

1. Copies every bundled `.zip` from `assets/plugins/` to
   `~/kodi-addons-to-install/`, where Kodi's file browser can reach them.
2. Writes `~/shell_command_launcher.menu`, substituting the real path to this
   repository so the menu entries actually work.

Kodi installs add-ons from inside its own interface, so the rest is manual —
but it is a five-minute job done once.

---

## First: allow unknown sources

Every add-on here lives outside the official Kodi repository. Kodi refuses to
install them until you turn this on:

> Settings → System → Add-ons → **Unknown sources** → On

---

## Installing the packages

> Settings → Add-ons → **Install from zip file** → Home folder →
> `kodi-addons-to-install`

Prefer the `repository.*` packages over one-off plugin zips: a repository
keeps its add-ons updated afterwards, a bare zip never updates.

### `repository.linuxaddons-1.0.1.zip` — Shell Script Launcher

**Install this one.** It is what gives you VPN control and UI switching from
inside Kodi, with no keyboard and no SSH.

1. Install the zip.
2. Settings → Add-ons → Install from repository → **Linux Add-on Repository**
   → Program add-ons → **Shell Script Launcher**.
3. Configure it: point **menu file** at `/home/pi/shell_command_launcher.menu`.
4. Right-click the add-on → **Add to Favourites**, so it is one press away.

Source: <https://github.com/wastis/LinuxAddonRepo>

**The menu it provides:**

| Entry | Does |
|---|---|
| Switch UI (next / previous) | Rotate to another environment |
| VPN status | Speaks the current connection |
| VPN next country | Advances through `NORDVPN_COUNTRIES` |
| VPN disconnect | Drops the tunnel |
| VPN Poland / Finland / UK / USA / Ukraine | Connect to a specific country |
| System temperature | Shows CPU and GPU temperature |
| Health check | Runs `doctor.sh` and shows the output |

Edit `assets/kodi/shell_command_launcher.menu` in the repository — **not** the
copy in your home directory — then re-run `./install.sh 20-kodi-addons`. The
installer rewrites `@REC_BIN@` into the real path each time.

Line format is `LABEL:MODE:COMMAND`, where MODE is `exitcode 0` (run quietly)
or `show` (display the output in a Kodi window).

### `repository.mtr81.zip` — Polish services

TVP VOD, Polsat Box Go, Player.pl and others.

> Install from repository → mtr81 repo → Video add-ons

Source: <https://mtr81.github.io/kodi_addons/>

### YouTube — download this one

**Not bundled.** The YouTube add-on breaks and gets re-released whenever
YouTube changes something, so a copy pinned in this repository would be stale
more often than not. Fetch the current release instead:

<https://github.com/anxdpanic/plugin.video.youtube/releases>

Download the `.zip` to `~/kodi-addons-to-install/` on the Pi and install it the
same way as the others:

```bash
cd ~/kodi-addons-to-install
wget https://github.com/anxdpanic/plugin.video.youtube/releases/download/<version>/plugin.video.youtube-<version>.zip
```

Keeping the previous release alongside it is worth doing — when an update
breaks playback, rolling back is the fastest fix.

**YouTube needs your own Google API key.** The add-on's shared keys are
routinely exhausted, which shows as "quota exceeded" or an empty home screen.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a project.
3. Enable **YouTube Data API v3**.
4. Credentials → Create credentials → **API key**, then again →
   **OAuth client ID** (type: TV and Limited Input devices).
5. In Kodi: YouTube add-on → Settings → API → enter the API key, client ID and
   client secret.
6. Sign in through the add-on when prompted.

Keep those credentials out of this repository — `.gitignore` covers
`*_api_key.txt`, but the right home for them is the add-on's own settings.

Newer releases: <https://github.com/anxdpanic/plugin.video.youtube/releases>

Screenshots: [`photos/youtube/`](../photos/youtube/).

### `plugin.video.yleareena.jade.zip` — Finnish Yle Areena

Finland's public broadcaster. Most content is geo-restricted to Finland — use
the VPN:

```bash
bash bin/nordvpn_connect.sh fi
```

The bundled zip was built from
<https://github.com/aajanki/plugin.video.yleareena.jade> with its own
`package.sh`.

---

## Netflix, Disney+ and other DRM services

These need **Widevine**, Google's DRM module. This is the fiddliest part of
the whole project, and the most likely to break when a service changes
something.

### 1. Install the add-on

The Netflix add-on comes from the CastagnaIT repository:
<https://github.com/CastagnaIT/plugin.video.netflix>

Follow that project's own installation instructions — it is updated far more
often than this document.

### 2. Install Widevine

`script.module.inputstreamhelper` (a dependency of the Netflix add-on) can
download and install Widevine for you. The first time you play protected
content it offers to do so; accept.

If it fails, the usual causes are no space on the SD card, or a Pi OS release
whose ARM Widevine build is unavailable.

### 3. Log in with an authentication key

Netflix blocks logins from unusual devices, so the recommended route is to log
in on a normal computer and transfer the resulting key.

Upstream instructions:
<https://github.com/CastagnaIT/plugin.video.netflix/wiki/Login-with-Authentication-key>

In outline:

1. On a desktop machine with Chrome, run the `NFAuthenticationKey.py` script
   the wiki links to.
2. It opens a browser, you log into Netflix, and it writes
   `NFAuthentication.key` plus a PIN.
3. Copy that file to the Pi.
4. In Kodi: Netflix add-on → Log in with authentication key → select the file
   → enter the PIN.

The key expires — expect to repeat this every few months.

**Do not commit the key file.** `.gitignore` covers `*.key`; it belongs in
`~/.kodi/userdata/addon_data/plugin.video.netflix/`.

### Known breakage: `preferredLocale`

A Netflix API change has, in the past, caused the add-on to crash on login
with a `KeyError` for `preferredLocale`, raised in:

```
~/.kodi/addons/plugin.video.netflix/resources/lib/utils/website.py
```

The fix is to make that lookup tolerate a missing key — read it with a default
instead of indexing directly — so the add-on falls back to a default locale
when Netflix omits the field.

Before patching anything by hand, **check whether upstream has already fixed
it**: this class of breakage is normally resolved within days.

- Issues: <https://github.com/CastagnaIT/plugin.video.netflix/issues>
- Read the actual traceback first: `~/.kodi/temp/kodi.log`

Any local edit you make here is overwritten by the next add-on update, which
is the desired outcome.

---

## Verify

```bash
./bin/doctor.sh kodi
```

Checks the menu file exists and no longer contains the `@REC_BIN@`
placeholder.

---

## Troubleshooting

**"Failed to install a dependency"**

Usually a missing repository. Install the `repository.*` zip first, then the
add-on from within it.

**"Installation from unknown sources is not allowed"**

Settings → System → Add-ons → Unknown sources → On.

**Shell Script Launcher shows nothing**

- Check the menu file path in the add-on's settings.
- Check the file exists: `cat ~/shell_command_launcher.menu`.
- If it still contains `@REC_BIN@`, re-run `./install.sh 20-kodi-addons`.

**A menu entry does nothing**

Run the same command over SSH to see the error:

```bash
bash bin/nordvpn_status.sh
```

**An add-on stops working after an update**

Common with unofficial add-ons. Check the add-on's own issue tracker; these
are usually fixed upstream within days. `~/.kodi/temp/kodi.log` has the
traceback.

**Playback fails on a DRM service**

- Confirm Widevine is installed: Settings → Add-ons → InputStream Helper →
  check Widevine status.
- Confirm `kodi-inputstream-adaptive` is installed.
- Check the SD card has free space — Widevine downloads need several hundred
  MB.
