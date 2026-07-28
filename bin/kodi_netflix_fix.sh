#!/bin/bash
# ---------------------------------------------------------------------------
# kodi_netflix_fix.sh - make the Netflix add-on usable again.
#
# Netflix retired its /api/shakti/mre/* endpoints and reshaped its Falcor
# content schema in June 2026. Add-on 1.23.5 is the newest release and upstream
# has had no commits since August 2025, so there is nothing to update to. Two
# separate things are broken, and this script fixes both:
#
#   STAGE 1 - "api"    Everything after login. Picking a profile fails with
#                      404 on .../memberapi/release/pathEvaluator, and with it
#                      go browsing, search, My List, Continue Watching,
#                      artwork, cast, year and resume positions.
#                      Fixed by a community patch vendored in
#                      assets/patches/ - see the README there for its
#                      provenance, and read it before you run it.
#
#   STAGE 2 - "login"  Login itself. You give the authentication key and its
#                      PIN, type your password, and land back at the
#                      login-method chooser. In the log:
#                        404 ... /api/shakti/mre/profilehub
#                      Fixed by a four-line change made here, because nobody
#                      upstream or in the issue thread has patched it.
#
# WHY SKIPPING THE LOGIN CHECK IS SOUND
#   Read login_auth_data() in access.py and note the order. Before it calls
#   profilehub the add-on has ALREADY loaded your auth-key cookies, fetched
#   /browse and parsed the session data (the real validation), and read your
#   account e-mail. The profilehub call only *confirms* the password you typed,
#   through the parental-control API. Its 404 discards a session that already
#   works - cookies.save() two lines later never runs.
#
#   Your password is still stored, because MSL EMAIL_PASSWORD authentication
#   needs it during playback. This removes a check, not a credential, so type
#   your real password. The cost: a wrong one now shows up as a playback
#   failure rather than at login.
#
# USAGE
#   bash bin/kodi_netflix_fix.sh              apply both stages
#   bash bin/kodi_netflix_fix.sh --login-only just the login fix
#   bash bin/kodi_netflix_fix.sh --status     report what is applied
#   bash bin/kodi_netflix_fix.sh --revert     restore the add-on as shipped
#
# Restart Kodi afterwards. Re-run after every add-on update - an update
# overwrites both patches, which is the outcome you want, since a genuine
# upstream fix should win. ./bin/doctor.sh kodi tells you when that has
# happened.
#
# See docs/20-kodi-addons.md and assets/patches/README.md.
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ADDON_DIR="${KODI_HOME:-$HOME/.kodi}/addons/plugin.video.netflix"
LIB_DIR="$ADDON_DIR/resources/lib"
ACCESS_PY="$LIB_DIR/services/nfsession/session/access.py"
BACKUP="$ADDON_DIR/.rec-original-lib.tar.gz"

API_PATCH="$REC_ASSETS/patches/netflix-api-fixes14.patch"
# Records which revision of the API patch is currently applied. Netflix keeps
# changing things and the patch series is revised every few weeks, so bumping
# the vendored file must restore the add-on and re-apply rather than try to
# stack one revision on top of another.
API_STAMP="$ADDON_DIR/.rec-api-patch"
# Something the community patch introduces and stock 1.23.5 does not have.
API_MARKER_FILE="$LIB_DIR/utils/api_requests.py"
API_MARKER="MY_LIST_GRAPHQL_MUTATIONS"
LOGIN_MARKER="rec-patch:profilehub-404"

mode="apply"
case "${1:-}" in
    --status)     mode="status" ;;
    --revert)     mode="revert" ;;
    --login-only) mode="login" ;;
    --help|-h)    sed -n '2,52p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "")           ;;
    *)            rec_die "Unknown option: $1  (try --help)" ;;
esac

[[ -f "$ACCESS_PY" ]] || rec_die "Netflix add-on not found at $ADDON_DIR
Install it from the CastagnaIT repository first - see docs/20-kodi-addons.md."

version="$(sed -n 's/.*id="plugin.video.netflix".*version="\([^"]*\)".*/\1/p' \
    "$ADDON_DIR/addon.xml" 2>/dev/null | head -1)"
[[ -n "$version" ]] || version="unknown"

api_applied()   { grep -q "$API_MARKER" "$API_MARKER_FILE" 2>/dev/null; }
login_applied() { grep -q "$LOGIN_MARKER" "$ACCESS_PY" 2>/dev/null; }

api_patch_name() { basename "$API_PATCH"; }
api_patch_sha()  { sha256sum "$API_PATCH" 2>/dev/null | cut -d' ' -f1; }
api_stamp_read() { [[ -f "$API_STAMP" ]] && cut -d' ' -f1 < "$API_STAMP"; }
api_stamp_name() { [[ -f "$API_STAMP" ]] && cut -d' ' -f2- < "$API_STAMP"; }

# The whole of resources/lib is backed up once, before anything is touched, so
# --revert is a restore rather than an attempt to reverse two patches that may
# have been applied in either order.
make_backup() {
    [[ -f "$BACKUP" ]] && return 0
    tar czf "$BACKUP" -C "$ADDON_DIR" resources/lib \
        || rec_die "Could not back up $LIB_DIR"
    rec_log "Backed up the original add-on to $BACKUP"
}

# An earlier version of this script did the login patch alone and kept a single
# access.py.rec-orig. Undo that first, so the tarball below captures a genuinely
# unmodified add-on and --revert means what it says. The login stage then
# re-applies as part of the normal run.
OLD_BACKUP="$ACCESS_PY.rec-orig"
migrate_old_backup() {
    [[ -f "$OLD_BACKUP" ]] || return 0
    if [[ -f "$BACKUP" ]]; then
        rm -f -- "$OLD_BACKUP"        # already superseded
        return 0
    fi
    rec_log "Converting the backup left by an earlier version of this script."
    cp -- "$OLD_BACKUP" "$ACCESS_PY" || rec_die "Could not restore $ACCESS_PY"
    rm -f -- "$OLD_BACKUP"
}

# -- status ----------------------------------------------------------------
if [[ "$mode" == "status" ]]; then
    rec_log "Netflix add-on version: $version"
    if api_applied; then
        if [[ "$(api_stamp_read)" == "$(api_patch_sha)" ]]; then
            rec_log "  [x] API patch: $(api_patch_name) (current)"
        else
            rec_log "  [~] API patch: $(api_stamp_name || echo 'an unrecorded revision') - OUT OF DATE"
            rec_log "      $(api_patch_name) is available; re-run to upgrade."
        fi
    else
        rec_log "  [ ] API patch - profiles and browsing will fail with a 404"
    fi
    if login_applied; then
        rec_log "  [x] Login patch (profilehub 404)"
    else
        rec_log "  [ ] Login patch - logging in will fail with a 404"
    fi
    [[ -f "$BACKUP" ]] && rec_log "Original add-on kept at: $BACKUP"
    exit 0
fi

# -- revert ----------------------------------------------------------------
if [[ "$mode" == "revert" ]]; then
    if [[ ! -f "$BACKUP" && -f "$OLD_BACKUP" ]]; then
        cp -- "$OLD_BACKUP" "$ACCESS_PY" || rec_die "Could not restore $ACCESS_PY"
        rm -f -- "$OLD_BACKUP"
        rec_log "Restored access.py from the earlier script's backup. Restart Kodi."
        exit 0
    fi
    if [[ ! -f "$BACKUP" ]]; then
        rec_log "Nothing to revert - no backup at $BACKUP"
        exit 0
    fi
    rm -rf -- "$LIB_DIR" || rec_die "Could not remove $LIB_DIR"
    tar xzf "$BACKUP" -C "$ADDON_DIR" || rec_die "Could not restore from $BACKUP"
    rm -f -- "$BACKUP" "$API_STAMP"
    rec_log "Restored the add-on as shipped. Restart Kodi."
    exit 0
fi

# -- apply -----------------------------------------------------------------
migrate_old_backup

if [[ "$version" != "1.23.5"* ]]; then
    rec_warn "Add-on version is $version, not 1.23.5 - both patches were written"
    rec_warn "against 1.23.5. Nothing will be applied unless it matches exactly."
    rec_warn "Check whether upstream has released a real fix:"
    rec_warn "  https://github.com/CastagnaIT/plugin.video.netflix/releases"
fi

# Stage 1: the community API patch.
if [[ "$mode" == "apply" ]]; then
    if api_applied && [[ "$(api_stamp_read)" == "$(api_patch_sha)" ]]; then
        rec_log "API patch: $(api_patch_name) already applied."
    elif api_applied && [[ ! -f "$BACKUP" ]]; then
        rec_error "A different revision of the API patch is applied, and there is no"
        rec_error "backup to undo it with. Revisions cannot be stacked."
        rec_die   "Reinstall the Netflix add-on, then re-run this script."
    elif [[ ! -f "$API_PATCH" ]]; then
        rec_warn "API patch not found at $API_PATCH - skipping stage 1."
    else
        # patch(1) is not installed by default on Raspberry Pi OS Lite.
        if rec_has patch; then
            patcher=(patch -p1 --forward --silent --directory "$ADDON_DIR")
            checker=(patch -p1 --forward --silent --dry-run --directory "$ADDON_DIR")
        elif rec_has git; then
            patcher=(git -C "$ADDON_DIR" apply -p1)
            checker=(git -C "$ADDON_DIR" apply -p1 --check)
        else
            rec_die "Neither 'patch' nor 'git' is available.  sudo apt install patch"
        fi

        # An older revision in place must be undone first - the revisions are
        # cumulative rewrites of the same files, not increments.
        if api_applied; then
            rec_log "Replacing $(api_stamp_name || echo 'an older API patch') with $(api_patch_name)."
            rm -rf -- "$LIB_DIR" || rec_die "Could not remove $LIB_DIR"
            tar xzf "$BACKUP" -C "$ADDON_DIR" || rec_die "Could not restore from $BACKUP"
            rm -f -- "$API_STAMP"
        fi

        if ! "${checker[@]}" < "$API_PATCH" >/dev/null 2>&1; then
            rec_error "The API patch does not apply to add-on $version."
            rec_error "The add-on source has changed - check whether the fix has landed:"
            rec_error "  https://github.com/CastagnaIT/plugin.video.netflix/issues/1792"
            rec_error "Continuing with the login patch only."
        else
            make_backup
            if "${patcher[@]}" < "$API_PATCH" >/dev/null 2>&1; then
                printf '%s %s\n' "$(api_patch_sha)" "$(api_patch_name)" > "$API_STAMP"
                rec_log "API patch applied: $(api_patch_name)"
            else
                rec_error "The API patch failed halfway. Restoring the original."
                rm -rf -- "$LIB_DIR"; tar xzf "$BACKUP" -C "$ADDON_DIR"
                rm -f -- "$API_STAMP"
                rec_die "Add-on restored; nothing was changed."
            fi
        fi
    fi
fi

# Stage 2: the login patch.
if login_applied; then
    rec_log "Login patch: already applied."
else
    make_backup
    python3 - "$ACCESS_PY" "$LOGIN_MARKER" <<'PYEOF'
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

    if (( $? != 0 )); then
        rec_error "Login patch not applied; $ACCESS_PY left untouched."
        rec_error "The add-on source has changed - check whether upstream has fixed this:"
        rec_die   "  https://github.com/CastagnaIT/plugin.video.netflix/issues/1781"
    fi
    rec_log "Login patch applied - the profilehub password check is now skipped."
fi

# Nothing here is worth leaving in place if Kodi cannot import it. Checked with
# compile() rather than compileall, so no __pycache__ is written into someone
# else's add-on.
python3 - "$LIB_DIR" <<'PYEOF' || rec_warn "Run --revert if Kodi misbehaves."
import pathlib, sys

bad = []
for path in pathlib.Path(sys.argv[1]).rglob('*.py'):
    try:
        compile(path.read_text(encoding='utf-8'), str(path), 'exec')
    except SyntaxError as exc:
        bad.append(f'  {path}: {exc}')

if bad:
    print('WARNING: these add-on modules do not compile:', file=sys.stderr)
    print('\n'.join(bad), file=sys.stderr)
    sys.exit(1)
PYEOF

rec_log ""
rec_log "Done (add-on $version). Restart Kodi, then log in with your key again."
rec_log "Enter your REAL Netflix password - it is still stored and used for"
rec_log "playback, it is only no longer checked up front."
rec_log ""
rec_log "Undo everything with:  bash bin/kodi_netflix_fix.sh --revert"
