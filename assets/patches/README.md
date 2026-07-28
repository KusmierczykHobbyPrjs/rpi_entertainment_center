# assets/patches

Third-party patches vendored here because the upstream project has not
released them and the add-on is unusable without them.

Applied by `bin/kodi_netflix_fix.sh`. Nothing here is applied automatically by
any installer — patching someone else's add-on is a decision you make
deliberately.

---

## `netflix-api-fixes10.patch`

| | |
|---|---|
| **Author** | [@go-vegan](https://github.com/go-vegan) |
| **Source** | [CastagnaIT/plugin.video.netflix issue #1792](https://github.com/CastagnaIT/plugin.video.netflix/issues/1792), comment of 1 July 2026 — [direct link to the file](https://github.com/user-attachments/files/29548501/netflix-api-fixes10.patch) |
| **Applies to** | `plugin.video.netflix` 1.23.5 (`+matrix.1`), unmodified |
| **Licence** | MIT, as the add-on it patches |
| **SHA-256** | `33055fd2e5d69bc3b2d03d4986b5e0ae0f1ba07b8cb76ccba85c1abe17a87454` |
| **Vendored** | 28 July 2026, byte-for-byte as posted |

**What it fixes.** Netflix retired `/api/shakti/mre/*` and reshaped its Falcor
content schema in June 2026, which broke `pathEvaluator` — the call behind
almost every screen in the add-on. Browsing, search, My List, Continue
Watching, artwork, cast and year, and resume positions all stopped working;
the add-on shows an error the moment you pick a profile. The patch reworks the
API layer, adds GraphQL fallbacks where the old paths are gone, and reshapes
the responses into what the rest of the add-on expects. 71 hunks across 18
files.

**What it does not fix.** Login. `resources/lib/services/nfsession/session/
access.py` is untouched, so the `profilehub` 404 during login remains — that is
what the second, much smaller patch in `bin/kodi_netflix_fix.sh` handles. The
two are independent and compose cleanly.

**Status.** Not merged upstream, and not reviewed by the add-on's author. It is
the tenth revision of a patch series maintained in the issue thread since June
2026 by users fixing what Netflix changed. Some reported it leaves search
returning a timeout for certain accounts. This is a community fix for an
unmaintained reverse-engineered client, offered because the alternative is an
add-on that does not work at all.

**Related work**, if you would rather use one of these:

- [`atrHusK/plugin.video.netflix`](https://github.com/atrHusK/plugin.video.netflix)
  — a fork that packages earlier revisions of this series as installable
  releases (v1.24.1, 29 June 2026). Easier to install; predates patches 9 and
  10, so missing artwork, cast, year and resume-position fixes.
- [PR #1783](https://github.com/CastagnaIT/plugin.video.netflix/pull/1783) —
  profile switching only, unmerged.

**Before using it, check whether it is still needed.** Upstream indicated on
1 July 2026 an intention to return to the project. A real release beats any of
this.

```bash
grep -o 'version="[^"]*"' ~/.kodi/addons/plugin.video.netflix/addon.xml | head -1
```

against <https://github.com/CastagnaIT/plugin.video.netflix/releases>.

---

## Verifying a vendored patch

The point of recording a hash is that you can confirm this file is what the
issue thread actually contains:

```bash
sha256sum assets/patches/netflix-api-fixes10.patch
curl -sL https://github.com/user-attachments/files/29548501/netflix-api-fixes10.patch | sha256sum
```

Read it before you run it. It is a large diff from a stranger on the internet,
running as your user, in an add-on you will hand your Netflix password to.
