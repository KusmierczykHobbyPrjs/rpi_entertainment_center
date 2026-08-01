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
3. Configure it: point **menu file** at `~/shell_command_launcher.menu`
   — the full path is printed by the installer, and is your home directory,
   not necessarily `/home/pi`.
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

> **Follow the add-on's own walkthrough** — it has screenshots of each Google
> Cloud Console page and is kept current as Google moves things around:
>
> **<https://github.com/anxdpanic/plugin.video.youtube/wiki/Personal-API-Keys>**

The short version, for orientation:

1. [Google Cloud Console](https://console.cloud.google.com/) → create a project.
2. **APIs & Services → Library** → enable **YouTube Data API v3**.
3. **Credentials → Create credentials → API key**.
4. **Credentials → Create credentials → OAuth client ID**, application type
   **TVs and Limited Input devices**. This gives you a client ID and secret.
5. In Kodi: YouTube → Settings → **API** → enter all three.
6. Sign in through the add-on when prompted (it shows a code to enter at
   google.com/device).

The OAuth step is the one people skip — an API key alone is not enough to sign
in to your account.

Keep those credentials in the add-on's settings, not in this repository.

Screenshots: [`photos/youtube/`](../photos/youtube/).

#### Sharing a "Mix" from the phone hangs Kodi — run the fix

Share an ordinary video or playlist from the YouTube app to Kore and it plays.
Share one of the generated mixes — the ones titled **"Mix - Artist - Title"**,
whose URL carries `&list=RD…` — and Kodi sits on
*"Updating playlist… 0%, 0/0"* for ever. Nothing plays, your whole daily API
quota is gone within minutes, and anything else that asks the player to do
something (`kodi-send`, the GPIO buttons, Kore itself) queues up behind a
plugin call that never returns.

```bash
bash bin/kodi_youtube_fix.sh
```

Restart Kodi and share the mix again; it starts within a couple of seconds,
queues the mix's distinct tracks and plays through them.

**Why it happens.** A mix is endless radio, not a playlist. YouTube does not
store one — it re-generates a rolling ~50-track window on every request, so
`playlistItems.list` never stops handing out a `nextPageToken`. Paging through
`RDdQw4w9WgXcQ` against the live API:

| Page | Items | Already seen | `nextPageToken` |
|---|---|---|---|
| 1 | 50 | — | `…QXpJLVlsQbEZZYw` |
| 2 | 49 | 48 | `…Qc1NV3JmWEc0RQ` |
| 3 | 49 | 48 | `…zR3dqZlVGeVk2TQ` |
| 4 | 49 | 47 | page 2's token again — and it cycles from here for ever |

Four pages are 197 queue entries but only **53 distinct videos**. Page 2 is
page 1 served again from the top: the first ten video IDs are identical.

`get_playlist_items()` in the add-on pages with `while 1:` and only stops when
a page arrives without a token. For a mix that never happens, so it fetches for
ever at one quota unit per request. The progress dialog reads 0/0 because the
total is only known once the fetch finishes — which it never does.

**The fix is two edits**, because stopping the loop is not enough on its own:

1. **`resource_manager.py` — stop paging when a page token comes round a second
   time.** A well-formed playlist never repeats one, so finite playlists page
   to the end exactly as before, and a mix stops after four pages. Both paging
   loops are patched: once the pages are cached, the cache pass spins the same
   way without even the network to slow it down.

   Deliberately not a page-count cap — real uploads playlists run to thousands
   of videos and a cap would silently truncate them.

2. **`yt_play.py` — queue each video once.** Without this you would get those
   197 entries: the same 50 songs four times over, in the same order. Scoped to
   `RD…` ids, because a hand-made playlist may repeat a track deliberately and
   that is none of our business.

3. **`yt_play.py` — hand Kodi a command, not a file**, so the queue survives.
   Kore shares by calling JSON-RPC `Player.Open` on the plugin URL, and Kodi
   treats that as **one playable file**. In `kodi.log`:

   ```
   Playlist.OnAdd ×12  playlistid 1     ← the add-on builds the queue
   Playlist.OnClear    playlistid 1     ← Kodi throws it away
   Playlist.OnAdd ×1   playlistid 1     ← replaced by the one resolved track
   ```

   and one song plays. Which playlist gets filled is decided by
   `XbmcPlaylistPlayer.get_playlist_id()`, which asks *whatever is playing at
   that moment* — so the queue sometimes lands in Kodi's **music** playlist and
   survives there instead, unused. That is the full music queue plus one-item
   video queue you see in Kore. The add-on's own source concedes the hazard:
   *"Sometimes Kodi gets confused and uses a music playlist for video content"*.

   So on the resolve path the add-on now returns
   `command://Playlist.PlayOffset(…)` instead of a media item. It runs that as
   a post-run action and starts its own playlist; Kodi has no file to play, so
   it never clears anything. This is the add-on's own mechanism — it already
   uses exactly this to recover from a stuck busy dialog.

   Verified on the Pi against a real `Player.Open`: `Builtin command queued:
   'Playlist.PlayOffset(video,0)'`, no `OnClear`, ten items left in the queue,
   and `Player.GoTo(next)` advanced 0 → 1 with the queue intact. A normal `PL…`
   playlist opened the same way also kept its 14 items — **this helps every
   shared playlist, not just mixes.**

The script records which revision it applied in
`~/.kodi/addons/plugin.video.youtube/.rec-youtube-patch`. Re-running after the
revision is bumped restores the add-on and applies the current set, rather than
stacking edits that are anchored on stock 7.4.4 source.

> **This bites you specifically because you followed the advice above and
> configured your own API key.** With the add-on's shared keys
> `v3_api_available()` is false, the add-on takes its InnerTube path instead,
> and mixes are unaffected. Removing your key to dodge this trades one bug for
> the quota-exhaustion it was meant to fix — patch instead.

Present in 7.4.4 (the current release) and unchanged on `master`; no issue is
filed upstream as of August 2026, so there is nothing to update to. Re-run the
script after every add-on update — an update overwrites the patch, which is
what you want, since a genuine upstream fix should win. `./bin/doctor.sh kodi`
tells you when it is needed. `--status` and `--revert` work as they do for the
Netflix script.

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

### 2. Install the crypto dependency

The add-on needs `pycryptodome`. **Install it with apt, not pip:**

```bash
sudo apt install python3-pycryptodome
```

> **Do not use `pip3 install`.** On Bookworm and later it fails with:
>
> ```
> error: externally-managed-environment
> ```
>
> That is [PEP 668](https://peps.python.org/pep-0668/) working as intended —
> Debian protects the system Python from pip. Do **not** work around it with
> `--break-system-packages`; the apt package is the correct answer and is what
> Kodi will find.

Older guides (including an earlier version of this one) also told you to
install **`win_inet_pton`**. Ignore that — it is a compatibility shim that
provides `inet_pton` on *Windows*, and is meaningless on Linux. It was
cargo-culted from a Windows install note and should never have been here.

In many cases you need nothing at all: the add-on declares
`script.module.pycryptodome` in its `addon.xml`, and Kodi installs that from
its own repository automatically. Only reach for apt if `~/.kodi/temp/kodi.log`
actually shows a `pycryptodomex`/`Crypto` import error.

> **Once it plays, it will probably play badly.** A Pi 3B decodes only H.264 in
> hardware, and Widevine decrypts in software on top of that.
> **[PERFORMANCE.md](PERFORMANCE.md)** covers which resolution and codec
> settings to use. Read it before reaching for InputStream Adaptive's bandwidth
> cap: that setting belongs to ISA rather than to the add-on you found it
> under, so it silently degrades every other streaming add-on too.

### 3. Install Widevine

`script.module.inputstreamhelper` (a dependency of the Netflix add-on) can
download and install Widevine for you. The first time you play protected
content it offers to do so; accept.

If it fails, the usual causes are no space on the SD card, or a Pi OS release
whose ARM Widevine build is unavailable.

### 4. Log in with an authentication key

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

---

## Other streaming services

Netflix is not the only one, and most work the same way — an add-on plus
Widevine plus your own account.

| Service | Add-on | Notes |
|---|---|---|
| **Disney+, HBO Max** | [SlyGuy add-ons](https://github.com/matthuisman/slyguy.addons) | One repository covering several services; `repository.slyguy` is the entry point. **No Netflix add-on** — that is CastagnaIT's only. |
| **Netflix** | [CastagnaIT](https://github.com/CastagnaIT/plugin.video.netflix) | The only option for Kodi. Breaks periodically — see below. |
| **BBC iPlayer** | [plugin.video.iplayerwww](https://github.com/Fraser1990/plugin.video.iplayerwww) | UK only — use the VPN: `bash bin/nordvpn_connect.sh uk` |
| **Yle Areena** (Finland) | [plugin.video.yleareena.jade](https://github.com/aajanki/plugin.video.yleareena.jade) | Bundled in `assets/plugins/`; geo-restricted to Finland |
| **TVP VOD, Polsat Box Go, Player.pl** (Poland) | [mtr81 repository](https://mtr81.github.io/kodi_addons/) | Bundled as `repository.mtr81.zip` |
| **Live TV / radio over IPTV** | PVR IPTV Simple Client | No account needed — see [15-kodi-iptv.md](15-kodi-iptv.md) |

Everything with DRM (Disney+, Prime, Netflix) needs **Widevine** and
`kodi-inputstream-adaptive`, exactly as described above for Netflix. If one of
them plays and another does not, the difference is almost always the service,
not your setup.

A general index of what exists: [Kodi add-on
directory](https://kodi.tv/addons/). Be sceptical of "all-in-one" add-ons
advertised elsewhere — many are piracy front-ends that break constantly.

---

### When it breaks: Netflix API changes

**Expect this add-on to break periodically, and to stay broken until upstream
patches it.** Netflix changes its internal "Shakti" API without notice. This is
the least stable component in the whole project, and nothing about your
configuration causes or fixes it.

The signature in `~/.kodi/temp/kodi.log` is an HTTP error on a `netflix.com`
API URL:

```
requests.exceptions.HTTPError: 404 Client Error: Not Found for url:
  https://www.netflix.com/api/shakti/mre/profilehub
```

A **404 is server-side**: that address does not exist. `mre` is not a
placeholder and not something the add-on failed to parse — it is a **hardcoded
constant** in the add-on, in
`resources/lib/services/nfsession/session/endpoints.py`:

```python
'profile_hub':
    {'address': '/api/shakti/mre/profilehub',
```

Netflix has retired the whole `/api/shakti/mre/*` family. Four endpoints use
it — `profilehub`, `profiles/switch`, `profileLock`, `contentRestrictions` —
so login, profile switching and parental controls all broke together. Because
the address is a constant rather than a value scraped per session, the
add-on's built-in "refresh the session and retry" recovery cannot help: it
retries the same dead URL. That is the second `Attempt to refresh the session
due to HTTP error 404` line in the log.

Reported repeatedly over the years, and open again through 2026:
[#1438](https://github.com/CastagnaIT/plugin.video.netflix/issues/1438)
(closed, 2022),
[#1781](https://github.com/CastagnaIT/plugin.video.netflix/issues/1781) and
[#1792](https://github.com/CastagnaIT/plugin.video.netflix/issues/1792) (both
open as of July 2026).

### What actually helps

**Updating does not.** `1.23.5+matrix.1` — the version in the log above — is
the newest release, and upstream has had no commits since August 2025. There
is nothing newer to install. Check before you assume otherwise:

```bash
grep -o 'version="[^"]*"' ~/.kodi/addons/plugin.video.netflix/addon.xml | head -1
```

against <https://github.com/CastagnaIT/plugin.video.netflix/releases>.

**What does help** is the next section: `bin/kodi_netflix_fix.sh` applies both
the login fix and a community API patch, which together get 1.23.5 working
again. If your symptom is not one of the two it covers:

1. **Check the tracker** for the exact endpoint from your log:
   <https://github.com/CastagnaIT/plugin.video.netflix/issues>. With upstream
   dormant, community patches appear in the issue threads long before any
   release — [#1792](https://github.com/CastagnaIT/plugin.video.netflix/issues/1792)
   is where the current work happens, and
   [PR #1783](https://github.com/CastagnaIT/plugin.video.netflix/pull/1783)
   covers profile switching.
2. **Watch it in the browser instead** — see below. There is no alternative
   Kodi add-on to switch to.

> **There is only one Netflix add-on for Kodi.** CastagnaIT's is it. The
> [SlyGuy add-ons](https://github.com/matthuisman/slyguy.addons) cover Disney+
> and HBO Max but **not Netflix** — it has been requested and does not exist.
> When CastagnaIT's is broken, Kodi cannot play Netflix at all.

### Fixing it: `bin/kodi_netflix_fix.sh`

```bash
bash bin/kodi_netflix_fix.sh          # apply both patches
bash bin/kodi_netflix_fix.sh --status # what is applied?
bash bin/kodi_netflix_fix.sh --revert # restore the add-on as shipped
```

Restart Kodi, then log in with your authentication key again.

**Two separate things are broken**, and the script fixes both:

| Stage | Symptom | Fix |
|---|---|---|
| **login** | Key and PIN accepted, password typed, back at the login-method chooser. `404 … /api/shakti/mre/profilehub` | Four lines, written here — see below |
| **api** | Login works; picking a profile errors immediately. `404 … /memberapi/release/pathEvaluator`. Also browsing, search, My List, Continue Watching, artwork, cast, year, resume positions | A community patch, vendored in [`assets/patches/`](../assets/patches/README.md) |

They are independent — neither patch touches the other's files — and the script
applies them in that order. `--login-only` skips the second if you would rather
not run a large third-party diff.

Before anything is modified the script tars up the add-on's `resources/lib`, so
`--revert` is a restore rather than an attempt to reverse two patches. It needs
`patch(1)`, falling back to `git apply`; on Raspberry Pi OS Lite you may need
`sudo apt install patch`.

> **Read [`assets/patches/README.md`](../assets/patches/README.md) before
> running this.** The API patch is 79 hunks across 21 files, written by a user
> in the upstream issue tracker, unreviewed by the add-on's author, and it runs
> in an add-on you will hand your Netflix password to. Its provenance and
> SHA-256 are recorded there so you can check it against the source.

#### The login patch

**Why skipping the check is sound.** Read `login_auth_data()` in
`resources/lib/services/nfsession/session/access.py` and note the order. Before
it ever calls `profilehub`, the add-on has already:

1. loaded your authentication-key cookies into the session
2. fetched `/browse` and parsed the session data — *this* is the real
   validation, and it passed
3. read your account e-mail off `/account/security`

The `profilehub` call is a **confirmation** that the password you just typed is
the right one, made through the parental-control API. Its 404 throws away a
session that already works — the `cookies.save()` two lines later never runs,
so a successful login is discarded.

The patch adds a `404` branch beside the existing `500` one, logs a warning and
carries on. Your password is still stored exactly as before, because the add-on
needs it for MSL `EMAIL_PASSWORD` authentication during playback — so **type
your real password**; the patch removes a check, not a credential.

The cost: a wrong password is no longer caught at login. It shows up later as a
playback failure instead.

It matches the exact 1.23.5 source block, so an upstream rewrite of that area
makes it a clean no-op rather than a mangle.

#### The API patch

Netflix retired `/api/shakti/mre/*` and reshaped its Falcor content schema in
June 2026, which broke `pathEvaluator` — the call behind nearly every screen.
`netflix-api-fixes14.patch` reworks the API layer and adds GraphQL fallbacks
where the old paths are simply gone. Full provenance, licence, hash and
revision history: [`assets/patches/README.md`](../assets/patches/README.md).

> **The revision number matters more than you would expect.** Netflix keeps
> changing things and the series is revised every week or two; a revision a
> few weeks old is not slightly behind, it is broken again. Empty menus, a
> genre that errors on opening, and a search that times out after 20 seconds
> are all symptoms of a stale revision rather than new faults.
>
> Revisions are cumulative rewrites of the same files and **cannot be
> stacked**, so the script restores the add-on and re-applies from scratch
> whenever the vendored file changes — including re-applying the login patch.
> `--status` names the revision in place.

Alternatives, if you would rather not run a vendored diff:

- [`atrHusK/plugin.video.netflix`](https://github.com/atrHusK/plugin.video.netflix)
  packages an earlier revision of the same work as an installable zip
  (v1.24.1). Simpler to install; predates the artwork, cast, year and
  resume-position fixes, and does **not** fix login either — you still want
  `--login-only` on top of it.
- Watch it in the browser instead, below.

#### Keeping it working

> **Re-run the script after every add-on update.** An update overwrites both
> patches — which is what you want, since a genuine upstream fix should win.
> `./bin/doctor.sh kodi` reports each patch separately and tells you when they
> need reapplying.

Neither patch survives a reinstall of the add-on, and neither is backed up by
`bin/backup.sh` — they are derived state, reproducible with one command.

### The fallback: Netflix in the browser

This project already has what you need — the desktop UI (module `40-desktop`)
and Chromium. Switch to the Desktop, open <https://www.netflix.com>, and play
from there. Chromium on Raspberry Pi OS ships with Widevine, so DRM works.

With module `45-kdeconnect` you can send the URL from your phone rather than
finding a keyboard:

> copy the link → KDE Connect → Send clipboard → Run command → Open clipboard URL

Expect a compromise rather than a fix:

- Netflix in a browser is capped at **720p** on Linux, and lower in practice.
- A Pi 3B is weak for browser video; it will be smoother on a Pi 4.
- No Kodi library integration, no remote — it is a browser on a TV.

It is the difference between watching something and not watching it.

### What does not help

- **Leaving the password prompt blank.** The failing call is guarded by
  `if password and ...` in `resources/lib/utils/api_requests.py`, which looks
  like it would skip it — but `is_success` then stays `False` and the add-on
  returns to the login-method chooser. Tested; it does not work.
- **Regenerating the authentication key.** A 404 means the request never
  reached an authenticating endpoint, so the key is not the problem. If the
  key were wrong you would see 401 or 403.
- **Reinstalling Widevine.** DRM is not involved until playback starts; this
  fails during login.
- **Updating the add-on.** There is nothing newer than 1.23.5 — see above.

### Patching by hand

Worth it when you can see the fix in the traceback and cannot wait. Any edit
under `~/.kodi/addons/plugin.video.netflix/` is overwritten by the next add-on
update — which is the outcome you want, since the real fix comes from upstream.

```bash
tail -100 ~/.kodi/temp/kodi.log
```

Two kinds of breakage are worth telling apart:

- **A crash on missing data is usually patchable.** A past example: a Netflix
  response stopped including `preferredLocale` and the add-on raised
  `KeyError` in `resources/lib/utils/website.py`. The fix was to read that key
  with a default rather than indexing it directly.
- **A 404 is patchable only if the call is dispensable.** No local edit brings
  back a deleted endpoint, so the question is what the response was *for*. The
  login 404 above qualifies — the answer was only a yes/no about your password
  — which is exactly what `bin/kodi_netflix_fix.sh` exploits. A 404 on a call
  that fetches content you then display does not: there is nothing to skip to.

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
