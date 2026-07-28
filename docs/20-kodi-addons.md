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

For the **login** failure specifically, this project ships a fix — see the
next section. For everything else:

1. **Check the tracker** for the exact endpoint from your log:
   <https://github.com/CastagnaIT/plugin.video.netflix/issues>. Community
   patches appear there before releases do; profile switching has one in
   [PR #1783](https://github.com/CastagnaIT/plugin.video.netflix/pull/1783),
   unmerged.
2. **Watch it in the browser instead** — see below. There is no alternative
   Kodi add-on to switch to.

> **There is only one Netflix add-on for Kodi.** CastagnaIT's is it. The
> [SlyGuy add-ons](https://github.com/matthuisman/slyguy.addons) cover Disney+
> and HBO Max but **not Netflix** — it has been requested and does not exist.
> When CastagnaIT's is broken, Kodi cannot play Netflix at all.

### Fixing the login

The login failure *is* fixable locally, because the call that fails does not
do anything the login needs.

```bash
bash bin/kodi_netflix_fix.sh          # apply
bash bin/kodi_netflix_fix.sh --status # is it applied?
bash bin/kodi_netflix_fix.sh --revert # undo
```

Restart Kodi, then log in with your authentication key again.

**Why skipping it is sound.** Read `login_auth_data()` in
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

The script keeps the original as `access.py.rec-orig`, matches the exact 1.23.5
source block (so an upstream rewrite makes it a clean no-op rather than a
mangle), refuses to leave a file that does not compile, and is safe to re-run.

> **Re-run it after every add-on update.** An update overwrites the patch —
> which is what you want, since a genuine upstream fix should win.
> `./bin/doctor.sh kodi` tells you when it needs reapplying.

**This gets you logged in. It does not fix everything else.** Netflix also
changed its Falcor content schema, which breaks browsing, search, My List and
Continue Watching for some accounts
([#1792](https://github.com/CastagnaIT/plugin.video.netflix/issues/1792)); and
profile switching hits the same dead `mre` address
([PR #1783](https://github.com/CastagnaIT/plugin.video.netflix/pull/1783)).
If those bite too, the browser below is the answer.

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
