#!/bin/bash
# ---------------------------------------------------------------------------
# kodi_netflix_fix.sh - let the Netflix add-on finish logging in again.
#
# Symptom this fixes (in ~/.kodi/temp/kodi.log):
#
#   requests.exceptions.HTTPError: 404 Client Error: Not Found for url:
#     https://www.netflix.com/api/shakti/mre/profilehub
#
# You choose "log in with an authentication key", give the key and its PIN,
# are asked for your account password, and are then dropped back at the
# login-method chooser with no useful error.
#
# WHY IT HAPPENS
#   Netflix retired the whole /api/shakti/mre/* address family. That address
#   is a hardcoded constant in the add-on (resources/lib/services/nfsession/
#   session/endpoints.py), not something it scrapes, so no amount of
#   reinstalling, re-keying or session refreshing can reach a live endpoint.
#   Add-on 1.23.5 is the newest release and upstream has been quiet since
#   August 2025, so there is nothing to update to.
#
# WHY IT IS SAFE TO SKIP
#   Read login_auth_data() in access.py and note the order of events. By the
#   time this call is made the add-on has ALREADY:
#     - loaded your auth-key cookies into the session
#     - fetched /browse and parsed the session data (the real validation)
#     - read your account e-mail off /account/security
#   The profilehub call adds nothing to that. It is a *confirmation* that the
#   password you typed is the right one, done through the parental-control
#   API. Its 404 throws away a session that already works.
#
#   The password itself is still stored, exactly as before - the add-on needs
#   it for MSL EMAIL_PASSWORD authentication during playback. So this patch
#   removes a check, not a credential. Type your real password.
#
#   The cost: a wrong password is no longer caught at login. It surfaces later
#   as a playback failure instead.
#
# USAGE
#   bash bin/kodi_netflix_fix.sh            apply the patch
#   bash bin/kodi_netflix_fix.sh --status   report whether it is applied
#   bash bin/kodi_netflix_fix.sh --revert   restore the original file
#
# Restart Kodi afterwards. Re-run this after every add-on update - an update
# overwrites the patch, which is the outcome you want, since a real upstream
# fix should win.
#
# See docs/20-kodi-addons.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ADDON_DIR="${KODI_HOME:-$HOME/.kodi}/addons/plugin.video.netflix"
TARGET="$ADDON_DIR/resources/lib/services/nfsession/session/access.py"
BACKUP="$TARGET.rec-orig"
MARKER="rec-patch:profilehub-404"

mode="apply"
case "${1:-}" in
    --status) mode="status" ;;
    --revert) mode="revert" ;;
    --help|-h) sed -n '2,50p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "") ;;
    *) rec_die "Unknown option: $1  (try --help)" ;;
esac

[[ -f "$TARGET" ]] || rec_die "Netflix add-on not found at $ADDON_DIR
Install it from the CastagnaIT repository first - see docs/20-kodi-addons.md."

version="$(sed -n 's/.*id="plugin.video.netflix".*version="\([^"]*\)".*/\1/p' \
    "$ADDON_DIR/addon.xml" 2>/dev/null | head -1)"
[[ -n "$version" ]] || version="unknown"

is_patched() { grep -q "$MARKER" "$TARGET"; }

# -- status ----------------------------------------------------------------
if [[ "$mode" == "status" ]]; then
    rec_log "Netflix add-on version: $version"
    if is_patched; then
        rec_log "The profilehub 404 patch IS applied."
    else
        rec_log "The profilehub 404 patch is NOT applied."
    fi
    [[ -f "$BACKUP" ]] && rec_log "Original file kept at: $BACKUP"
    exit 0
fi

# -- revert ----------------------------------------------------------------
if [[ "$mode" == "revert" ]]; then
    if [[ ! -f "$BACKUP" ]]; then
        rec_log "Nothing to revert - no backup at $BACKUP"
        exit 0
    fi
    cp -- "$BACKUP" "$TARGET" || rec_die "Could not restore $TARGET"
    rm -f -- "$BACKUP"
    rec_log "Restored the original access.py. Restart Kodi."
    exit 0
fi

# -- apply -----------------------------------------------------------------
if is_patched; then
    rec_log "Already patched (add-on $version) - nothing to do."
    exit 0
fi

# 1.23.5 is what this was written against. A different version is not fatal:
# the patch is applied by matching the exact source block, so it either finds
# it or refuses. But say so, because a newer release may have fixed this.
if [[ "$version" != "1.23.5"* ]]; then
    rec_warn "Add-on version is $version, not 1.23.5 - this patch was written"
    rec_warn "against 1.23.5. If the block has changed, nothing will be touched."
fi

[[ -f "$BACKUP" ]] || cp -- "$TARGET" "$BACKUP" || rec_die "Could not back up $TARGET"

python3 - "$TARGET" "$MARKER" <<'PYEOF'
import sys

path, marker = sys.argv[1], sys.argv[2]

# The exact block as shipped in 1.23.5. Matching the whole thing rather than a
# regex means an upstream rewrite of this area is a clean no-op, not a mangle.
OLD = """        except exceptions.HTTPError as exc:
            if exc.response.status_code == 500:
                # This endpoint raise HTTP error 500 when the password is wrong
                raise LoginError(common.get_local_string(12344)) from exc
            raise
"""

NEW = f"""        except exceptions.HTTPError as exc:
            if exc.response.status_code == 500:
                # This endpoint raise HTTP error 500 when the password is wrong
                raise LoginError(common.get_local_string(12344)) from exc
            if exc.response.status_code == 404:
                # {marker} - applied by rpi_entertainment_center
                # Netflix retired /api/shakti/mre/*, so the password cannot be
                # verified any more. Everything that actually authenticates the
                # session (cookies, /browse, the account e-mail) has already
                # succeeded above, so accept the login instead of discarding it.
                LOG.warn('Password not verified: profilehub returned 404 '
                         '(patched by rpi_entertainment_center)')
            else:
                raise
"""

with open(path, encoding='utf-8') as fh:
    src = fh.read()

count = src.count(OLD)
if count != 1:
    sys.exit(f'expected the 1.23.5 error-handling block exactly once, found {count}')

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src.replace(OLD, NEW))

# Refuse to leave a file Kodi cannot import.
try:
    compile(open(path, encoding='utf-8').read(), path, 'exec')
except SyntaxError as exc:
    sys.exit(f'patched file does not compile: {exc}')
PYEOF

status=$?
if (( status != 0 )); then
    cp -- "$BACKUP" "$TARGET"
    rec_die "Patch not applied; $TARGET left untouched.
The add-on source has changed - check whether upstream has fixed this:
  https://github.com/CastagnaIT/plugin.video.netflix/issues/1781"
fi

rec_log "Patched $TARGET  (add-on $version)"
rec_log "Original saved as $BACKUP"
rec_log ""
rec_log "Now: restart Kodi, then log in with your authentication key again."
rec_log "Enter your REAL Netflix password at the password prompt - it is still"
rec_log "stored and used for playback, it is only no longer checked up front."
