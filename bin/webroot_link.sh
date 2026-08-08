#!/bin/bash
# ---------------------------------------------------------------------------
# webroot_link.sh - publish a folder from your home directory as part of the site.
#
# THE PROBLEM
#   Keeping a site in ~/public_html instead of /var/www/html is the sane
#   arrangement: it is yours, it needs no sudo to edit, and it is included in
#   a home-directory backup. The obvious way to wire it up is a symlink:
#
#       sudo ln -s /home/pi/public_html/memes /var/www/html/memes
#       sudo chmod -R o+rX /var/www/html/memes
#
#   and the result is "Forbidden. You don't have permission to access this
#   resource." The permissions on the folder itself look perfect, which is
#   what makes this so hard to debug.
#
#   Apache runs as www-data, and reaching a file needs the execute bit on
#   EVERY directory above it - not just on the folder you chmod'ed. Raspberry
#   Pi OS creates home directories as drwx------, owner only, so www-data
#   cannot enter /home/pi at all and nothing done further down can rescue it.
#   Apache's error log says
#
#       AH00037: Symbolic link not allowed or link target not accessible
#
#   but the browser only ever says "Forbidden".
#
# WHAT THIS DOES
#   1. Grants www-data permission to traverse the directories leading to your
#      folder - with an ACL, not chmod o+x, so your home directory does not
#      become readable by every other account on the machine.
#   2. Grants www-data read access to the folder itself, including a default
#      ACL so files you add later inherit it.
#   3. Links it into the document root.
#   4. Blocks .git and other dotfiles from being served, because a published
#      working copy otherwise hands out its whole history.
#   5. Fetches the result over HTTP and tells you what actually happened.
#
# USAGE
#   bash bin/webroot_link.sh memes             publish ~/public_html/memes at /memes
#   bash bin/webroot_link.sh memes --as blog   ... at /blog instead
#   bash bin/webroot_link.sh ~/sites/thing     any path, not just ~/public_html
#   bash bin/webroot_link.sh --list            show what is published
#   bash bin/webroot_link.sh --remove memes    unpublish (your files are untouched)
#
# See docs/80-webserver.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../lib/install_helpers.sh"

require_not_root

# Overridable for a non-default DocumentRoot; the stock Debian one otherwise.
DOCROOT="${REC_DOCROOT:-/var/www/html}"
SRC_BASE="${REC_PUBLIC_HTML:-$HOME/public_html}"
WWW_USER="$(rec_www_user)"

# Prints the USAGE block from the header above, so the two can never drift.
usage() {
    awk '/^# USAGE$/ {p=1} p && /^# -{20,}/ {exit} p' "$(readlink -f "$0")" \
        | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# --- Sub-commands ----------------------------------------------------------

list_published() {
    step "Published under $DOCROOT"
    local link target found=0
    for link in "$DOCROOT"/*; do
        [[ -L "$link" ]] || continue
        found=1
        target="$(readlink -f "$link" 2>/dev/null)"
        if [[ -z "$target" || ! -e "$target" ]]; then
            fail "  /$(basename "$link") -> $(readlink "$link")  (BROKEN: target is gone)"
        elif rec_www_untraversable "$target" "$WWW_USER" >/dev/null; then
            fail "  /$(basename "$link") -> $target  (unreachable by $WWW_USER)"
            note "    Repair it: bash bin/webroot_link.sh $(basename "$link")"
        else
            ok "  /$(basename "$link") -> $target"
        fi
    done
    (( found )) || skip "  Nothing is linked in from elsewhere"
}

remove_published() {
    # Two statements on purpose: bash expands every argument to `local` before
    # creating any of them, so a one-liner referring to $name would read the
    # (unset) global and die under `set -u`.
    local name="$1"
    local link="$DOCROOT/$name"
    if [[ ! -L "$link" ]]; then
        fail "$link is not a symlink - refusing to touch it"
        note "This script only removes links it could have created."
        exit 1
    fi
    step "Unpublishing /$name"
    note "Removing the link only. $(readlink -f "$link") stays exactly as it is."
    sudo rm -f "$link"
    ok "Removed $link"
    note "The ACLs granted to $WWW_USER are left in place; other links may rely"
    note "on them. Revoke by hand if you want: sudo setfacl -x u:$WWW_USER $HOME"
}

# --- Argument parsing ------------------------------------------------------

SRC_ARG=""
LINK_NAME=""

while (( $# )); do
    case "$1" in
        --list)    list_published; exit 0 ;;
        --remove)  [[ -n "${2:-}" ]] || { fail "--remove needs a name"; exit 1; }
                   remove_published "$2"; exit 0 ;;
        --as)      [[ -n "${2:-}" ]] || { fail "--as needs a name"; exit 1; }
                   LINK_NAME="$2"; shift 2; continue ;;
        -h|--help) usage 0 ;;
        -*)        fail "Unknown option: $1"; usage 1 ;;
        *)         if [[ -n "$SRC_ARG" ]]; then fail "Too many arguments"; usage 1; fi
                   SRC_ARG="$1" ;;
    esac
    shift
done

if [[ -z "$SRC_ARG" ]]; then
    fail "Nothing to publish."
    usage 1
fi

# A bare name means "inside ~/public_html"; anything with a slash is a path.
if [[ "$SRC_ARG" == */* || "$SRC_ARG" == "~"* ]]; then
    SRC="$(readlink -f "${SRC_ARG/#\~/$HOME}" 2>/dev/null)"
else
    SRC="$(readlink -f "$SRC_BASE/$SRC_ARG" 2>/dev/null)"
fi
LINK_NAME="${LINK_NAME:-$(basename "${SRC_ARG%/}")}"
LINK="$DOCROOT/$LINK_NAME"

if [[ -z "$SRC" || ! -d "$SRC" ]]; then
    fail "Not a directory: ${SRC:-$SRC_ARG}"
    if [[ "$SRC_ARG" != */* ]]; then
        note "Expected it under $SRC_BASE. Create it first:"
        note "  mkdir -p $SRC_BASE/$SRC_ARG"
    fi
    exit 1
fi

if [[ ! -d "$DOCROOT" ]]; then
    fail "No document root at $DOCROOT - is Apache installed?"
    note "Install the web server first: ./install.sh 80-webserver"
    exit 1
fi

step "Publishing $SRC as /$LINK_NAME"

# --- 1. Traverse permission on the path ------------------------------------
# This is the actual cause of the "Forbidden" that sends people in circles.
step "Giving $WWW_USER a way in"

if ! rec_has setfacl; then
    apt_install acl || exit 1
fi

blockers="$(rec_www_untraversable "$SRC" "$WWW_USER")"
if [[ -z "$blockers" ]]; then
    skip "$WWW_USER can already reach $SRC"
else
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        # Execute only - the right to pass THROUGH the directory. It does not
        # grant a listing of its contents, so the rest of your home directory
        # stays as private as it was.
        if sudo setfacl -m "u:$WWW_USER:x" "$dir" 2>/dev/null; then
            ok "  $dir - $WWW_USER may now traverse it (not list it)"
        else
            fail "  $dir - setfacl failed"
            note "    Fallback (opens it to every local user): sudo chmod o+x $dir"
        fi
    done <<<"$blockers"
fi

# --- 2. Read access to the content -----------------------------------------
step "Granting read access to the content"
# -R applies to what is there now; -d sets the DEFAULT acl, which new files
# and folders inherit - otherwise tomorrow's upload is a fresh 403.
if sudo setfacl -R -m "u:$WWW_USER:rX" "$SRC" 2>/dev/null &&
   sudo setfacl -R -d -m "u:$WWW_USER:rX" "$SRC" 2>/dev/null; then
    ok "$WWW_USER can read the folder, and will inherit access to new files"
else
    fail "Could not set ACLs on $SRC"
    note "Fallback: sudo chmod -R o+rX $SRC  (and repeat it after adding files)"
fi

# --- 3. The link -----------------------------------------------------------
step "Linking it into the document root"
if [[ -L "$LINK" ]]; then
    current="$(readlink -f "$LINK")"
    if [[ "$current" == "$SRC" ]]; then
        skip "$LINK already points at $SRC"
    else
        note "Repointing $LINK: was $current"
        sudo ln -sfn "$SRC" "$LINK"
        ok "$LINK -> $SRC"
    fi
elif [[ -e "$LINK" ]]; then
    fail "$LINK already exists and is not a symlink - refusing to replace it"
    note "Publish under a different name: bash bin/webroot_link.sh $SRC_ARG --as something-else"
    exit 1
else
    sudo ln -s "$SRC" "$LINK"
    ok "$LINK -> $SRC"
fi

# Apache must also be allowed to follow it. Debian's stock <Directory /var/www/>
# has FollowSymLinks, but a hand-edited vhost may not.
if grep -rqs "FollowSymLinks\|SymLinksIfOwnerMatch" /etc/apache2/apache2.conf \
        /etc/apache2/sites-enabled/ 2>/dev/null; then
    ok "Apache is configured to follow symlinks"
else
    fail "No FollowSymLinks anywhere in the Apache config - the link will 403"
    note "Add 'Options +FollowSymLinks' to the <Directory $DOCROOT> block."
fi

# --- 4. Do not serve the repository ----------------------------------------
step "Keeping private files private"
rec_apache_harden_paths

if [[ -d "$SRC/.git" ]]; then
    note "$SRC is a git working copy - .git is now blocked by the rule above."
    note "Verify after any Apache change:  curl -s -o /dev/null -w '%{http_code}\\n' \\"
    note "    http://localhost/$LINK_NAME/.git/config     # must NOT be 200"
fi

# --- 5. Prove it works -----------------------------------------------------
step "Checking it over HTTP"
code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost/$LINK_NAME/" 2>/dev/null)"
case "$code" in
    200|30[1237])
        ok "http://localhost/$LINK_NAME/ returns $code - it is being served"
        ;;
    403)
        fail "Still 403 Forbidden"
        note "Read the real reason: sudo tail -5 /var/log/apache2/error.log"
        note "A 403 with no index.html/index.php is also normal - this project"
        note "disables directory listings on purpose."
        ;;
    404)
        fail "404 - Apache found no index file in $SRC"
        note "Add an index.html or index.php, or request a file directly."
        ;;
    500)
        fail "500 - the files are reachable, but your PHP raised an error"
        note "That is your application, not the web server: sudo tail -5 /var/log/apache2/error.log"
        ;;
    000|"")
        fail "Could not reach Apache on localhost at all"
        note "systemctl status apache2"
        ;;
    *)
        note "http://localhost/$LINK_NAME/ returned $code"
        ;;
esac

echo
ok "Done."
cat <<EOF

  Local     http://localhost/$LINK_NAME/
  On the LAN  http://$(hostname -I | awk '{print $1}')/$LINK_NAME/

  Edit the files as your normal user, in $SRC - no sudo needed.
  New files inherit web access automatically (default ACL).

  bash bin/webroot_link.sh --list             what is published
  bash bin/webroot_link.sh --remove $LINK_NAME   unpublish
EOF
