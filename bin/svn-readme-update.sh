#!/usr/bin/env bash
#
# Readme-only update of already-published plugins on WP.org SVN (e.g. a "Tested up to" bump):
# copy the dev source's readme.txt into trunk/ AND tags/<Stable tag>/, show the diff, and STOP
# unless --commit is given. No version bump, no code changes, assets/ untouched.
#
# Refuses a plugin when the readme diff touches anything other than the "Tested up to" line,
# unless --any-change is given (so an unreleased changelog never slips out by accident).
#
# Usage:
#   svn-readme-update.sh [--commit] [--any-change] <slug> [<slug> ...]
#   svn-readme-update.sh [--commit] [--any-change] --published   # every 'published' slug in submission-queue.txt

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$(dirname "$DEV_TOOLS_DIR")/wp-content/plugins"
SVN_ROOT="/Volumes/www/svn"

COMMIT=0
ANY=0
SLUGS=()
for a in "$@"; do
    case "$a" in
        --commit) COMMIT=1 ;;
        --any-change) ANY=1 ;;
        --published) while read -r s st _; do [ "$st" = published ] && SLUGS+=("$s"); done < <(grep -v '^#' "$DEV_TOOLS_DIR/submission-queue.txt") ;;
        *) SLUGS+=("$a") ;;
    esac
done
[ ${#SLUGS[@]} -gt 0 ] || { echo "Usage: $0 [--commit] [--any-change] <slug>... | --published" >&2; exit 1; }

OK=0; FAIL=0; SAME=0
for slug in "${SLUGS[@]}"; do
    SRC="$PLUGINS_DIR/$slug/readme.txt"
    WC="$SVN_ROOT/$slug"
    if [ ! -f "$SRC" ]; then echo "✗ $slug: no dev readme"; FAIL=$((FAIL+1)); continue; fi
    if [ ! -d "$WC/.svn" ]; then
        svn co -q "https://plugins.svn.wordpress.org/$slug" "$WC" || { echo "✗ $slug: checkout failed"; FAIL=$((FAIL+1)); continue; }
    else
        svn up -q "$WC" || { echo "✗ $slug: svn up failed"; FAIL=$((FAIL+1)); continue; }
    fi
    STABLE=$(grep -m1 -E '^Stable tag:' "$WC/trunk/readme.txt" | sed 's/Stable tag:[[:space:]]*//' | tr -d ' \r')
    if [ -z "$STABLE" ] || [ ! -d "$WC/tags/$STABLE" ]; then echo "✗ $slug: tags/$STABLE missing in SVN"; FAIL=$((FAIL+1)); continue; fi
    DEV_STABLE=$(grep -m1 -E '^Stable tag:' "$SRC" | sed 's/Stable tag:[[:space:]]*//' | tr -d ' \r')
    if [ "$DEV_STABLE" != "$STABLE" ]; then echo "✗ $slug: dev Stable tag $DEV_STABLE != SVN $STABLE (needs a real release, use svn-release.sh)"; FAIL=$((FAIL+1)); continue; fi

    CHANGED=0
    for t in "trunk" "tags/$STABLE"; do
        if ! cmp -s "$SRC" "$WC/$t/readme.txt"; then
            OTHER=$(diff "$WC/$t/readme.txt" "$SRC" | grep -E '^[<>]' | grep -vE '^[<>] Tested up to:' | head -3)
            if [ -n "$OTHER" ] && [ $ANY -eq 0 ]; then
                echo "✗ $slug: $t readme differs beyond 'Tested up to' (re-run with --any-change if intended):"
                echo "$OTHER" | sed 's/^/      /'
                CHANGED=-1; break
            fi
            cp "$SRC" "$WC/$t/readme.txt"; CHANGED=1
        fi
    done
    [ $CHANGED -eq -1 ] && { svn revert -q "$WC/trunk/readme.txt" "$WC/tags/$STABLE/readme.txt"; FAIL=$((FAIL+1)); continue; }
    if [ $CHANGED -eq 0 ]; then echo "= $slug: already up to date"; SAME=$((SAME+1)); continue; fi

    TESTED=$(grep -m1 -E '^Tested up to:' "$SRC" | sed 's/Tested up to:[[:space:]]*//' | tr -d ' \r')
    if [ $COMMIT -eq 1 ]; then
        svn commit -q "$WC/trunk/readme.txt" "$WC/tags/$STABLE/readme.txt" -m "Readme update: tested up to $TESTED" --non-interactive \
            && { echo "✓ $slug: committed trunk + tags/$STABLE (tested up to $TESTED)"; OK=$((OK+1)); } \
            || { echo "✗ $slug: commit failed"; FAIL=$((FAIL+1)); }
    else
        echo "~ $slug: trunk + tags/$STABLE readme ready (tested up to $TESTED)"; OK=$((OK+1))
    fi
done

echo
[ $COMMIT -eq 1 ] && echo "Committed: $OK   Already current: $SAME   Failed: $FAIL" \
                  || echo "Prepared: $OK   Already current: $SAME   Failed: $FAIL   (nothing committed; re-run with --commit)"
