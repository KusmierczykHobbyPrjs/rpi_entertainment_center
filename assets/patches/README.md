# assets/patches

Third-party patches vendored here because the upstream project has not
released them and the add-on is unusable without them.

Applied by `bin/kodi_netflix_fix.sh`. Nothing here is applied automatically by
any installer — patching someone else's add-on is a decision you make
deliberately.

---

## `netflix-api-fixes14.patch`

| | |
|---|---|
| **Author** | [@go-vegan](https://github.com/go-vegan) |
| **Source** | [CastagnaIT/plugin.video.netflix issue #1792](https://github.com/CastagnaIT/plugin.video.netflix/issues/1792), comment of 28 July 2026 — [direct link to the file](https://github.com/user-attachments/files/30440428/netflix-api-fixes14.patch) |
| **Applies to** | `plugin.video.netflix` 1.23.5 (`+matrix.1`), unmodified |
| **Licence** | MIT, as the add-on it patches |
| **SHA-256** | `d7a2b0350b5ea4a0bc529f262040a721ffc3d9067d926363ffad351b597fb4af` |
| **Vendored** | 28 July 2026, byte-for-byte as posted |

**What it fixes.** Netflix retired `/api/shakti/mre/*` and reshaped its Falcor
content schema in June 2026, which broke `pathEvaluator` — the call behind
almost every screen in the add-on. Browsing, search, My List, Continue
Watching, artwork, cast, year and resume positions all stopped working; the
add-on shows an error the moment you pick a profile. The patch reworks the API
layer, adds GraphQL fallbacks where the old paths are gone, and reshapes the
responses into what the rest of the add-on expects. 79 hunks across 21 files.

**What it does not fix.** Login. `resources/lib/services/nfsession/session/
access.py` is untouched, so the `profilehub` 404 during login remains — that is
what the second, much smaller patch in `bin/kodi_netflix_fix.sh` handles. The
two are independent and compose cleanly. Other users have hit the same login
wall and the patch author has said he would rather not touch that code, so do
not expect a revision to make our login patch redundant.

**Status.** Not merged upstream, and not reviewed by the add-on's author. It is
the fourteenth revision of a patch series maintained in the issue thread since
June 2026 by users fixing what Netflix changes.

---

### Why the revision matters

Netflix changes things and the series is revised every week or two. **A
revision that is a few weeks old is not "slightly behind" — it is broken**, in
the same way the unpatched add-on is broken. Around 14 July 2026 a Netflix-side
change emptied My List, All TV Shows and All Movies for everyone on revision 12
or earlier, and made search time out.

Known symptoms of running a stale revision, all of which look like new bugs:

| In `kodi.log` | What you see |
|---|---|
| `Falling back to empty LoCo root menu after pathEvaluator 404` | Main menu categories empty or nearly so |
| `No current LoCo root id found in browse page` | A genre or list opens, then errors |
| `TimeoutError: timed out` in `common/ipc.py` | Search spins for 20 seconds, then fails |

The relevant history, so you can tell what a given revision does and does not
have:

| Revision | Fixes |
|---|---|
| 10 (1 Jul) | Cast, year, resume positions |
| 11 (9 Jul) | Search timeout, thumbnails |
| 12 (9 Jul) | Portrait thumbnails, Add to My List |
| **13 (16 Jul)** | **Search; empty My List / All TV Shows / All Movies; Continue Watching truncated to 8; thumbnails** — this is the one that recovers from Netflix's mid-July change |
| **14 (28 Jul)** | Trailer handling, slow reload of "New on Netflix", Python 3.8 compatibility, UTF-8 in Continue Watching |

**To check for a newer one**, read the tail of
[issue #1792](https://github.com/CastagnaIT/plugin.video.netflix/issues/1792).
Revisions are posted as `netflix-api-fixesNN.patch` attachments. To adopt one,
drop it in this directory and point `API_PATCH` in `bin/kodi_netflix_fix.sh` at
it; the script notices the change, restores the add-on and applies the new
revision, because revisions are cumulative rewrites of the same files and
**cannot be stacked**.

`bash bin/kodi_netflix_fix.sh --status` tells you which revision is in place.

---

### Related work

- [`atrHusK/plugin.video.netflix`](https://github.com/atrHusK/plugin.video.netflix)
  — a fork that packages earlier revisions of this series as installable
  releases (v1.24.1, 29 June 2026). Easier to install, but it predates the
  mid-July fixes and does not fix login either.
- [PR #1783](https://github.com/CastagnaIT/plugin.video.netflix/pull/1783) —
  profile switching only, unmerged.

**Before using any of it, check whether it is still needed.** Upstream
indicated on 1 July 2026 an intention to return to the project. A real release
beats all of this.

```bash
grep -o 'version="[^"]*"' ~/.kodi/addons/plugin.video.netflix/addon.xml | head -1
```

against <https://github.com/CastagnaIT/plugin.video.netflix/releases>.

---

## Verifying a vendored patch

The point of recording a hash is that you can confirm this file is what the
issue thread actually contains:

```bash
sha256sum assets/patches/netflix-api-fixes14.patch
curl -sL https://github.com/user-attachments/files/30440428/netflix-api-fixes14.patch | sha256sum
```

Read it before you run it. It is a large diff from a stranger on the internet,
running as your user, in an add-on you will hand your Netflix password to. Its
author describes it as "quick and dirty fixes" and says it should not be relied
upon — which is honest, and worth taking at face value.
