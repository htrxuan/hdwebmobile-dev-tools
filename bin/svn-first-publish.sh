#!/usr/bin/env bash
#
# First WP.org SVN release of a newly approved plugin: checkout, copy code into trunk/ and
# marketing images into assets/, then STOP for review unless --commit is given.
#
# Lessons baked in (see memory wp_org_publication_status):
#   - never blind-rsync a plugin folder into trunk: dev-only files (node_modules, *.py,
#     package.json, README.md, LICENSE, .git) leaked into a working copy once -- copy only
#     what `git ls-files` tracks, minus the same exclusions build-zips.sh uses;
#   - verify trunk is byte-identical to the dev source before committing;
#   - assets/ holds icon/banner/screenshot PNGs (and icon.svg if present), never trunk/assets.
#
# Usage:
#   svn-first-publish.sh <slug>            # prepare + show svn status, commit nothing
#   svn-first-publish.sh <slug> --commit   # also commit trunk, assets, and tags/<version>

set -u
SLUG="${1:?usage: svn-first-publish.sh <slug> [--commit]}"
COMMIT="${2:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/wp-content/plugins/$SLUG"
WC="/Volumes/www/svn/$SLUG"
URL="https://plugins.svn.wordpress.org/$SLUG"

[ -d "$SRC/.git" ] || { echo "No git repo at $SRC"; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/")" = 200 ] || { echo "$URL does not exist -- not approved yet?"; exit 1; }
[ -z "$(git -C "$SRC" status --porcelain)" ] || { echo "Dev source has uncommitted changes -- commit them first"; exit 1; }

VER=$(grep -m1 -E '^\s*\*\s*Version:' "$SRC/$SLUG.php" | sed 's/.*Version:\s*//' | tr -d ' \r')
[ -n "$VER" ] || { echo "Could not read Version header"; exit 1; }

if [ -d "$WC/.svn" ]; then svn up -q "$WC"; else svn co -q "$URL" "$WC"; fi || { echo "svn checkout/update failed"; exit 1; }
mkdir -p "$WC/trunk" "$WC/assets" "$WC/tags"
[ -e "$WC/tags/$VER" ] && { echo "tags/$VER already exists in SVN -- nothing to do"; exit 1; }

# Code: exactly the git-tracked files, minus repo-only files and marketing images.
git -C "$SRC" ls-files | grep -vE '^(\.gitignore|README\.md|LICENSE)$|^assets/[^/]+\.(png|jpe?g|gif)$|^assets/icon\.svg$' |
while read -r f; do
  mkdir -p "$WC/trunk/$(dirname "$f")"
  cp "$SRC/$f" "$WC/trunk/$f"
done
# Marketing images -> top-level assets/
for f in "$SRC"/assets/{icon-*.png,banner-*.png,screenshot-*.png,icon.svg}; do
  [ -f "$f" ] && cp "$f" "$WC/assets/"
done

svn add -q --force "$WC/trunk" "$WC/assets"
for f in "$WC"/assets/*.png; do [ -f "$f" ] && svn propset -q svn:mime-type image/png "$f"; done
for f in "$WC"/assets/*.svg; do [ -f "$f" ] && svn propset -q svn:mime-type image/svg+xml "$f"; done

# Verify: trunk == dev source (same exclusions), and nothing unexpected in the working copy.
DIFF=$(diff -rq -x .svn -x .git -x .gitignore -x README.md -x LICENSE -x .DS_Store -x assets "$WC/trunk" "$SRC" 2>&1 | grep -v '^Only in '"$SRC"': assets$')
UNVERSIONED=$(svn status "$WC" | grep '^?')
echo "== $SLUG $VER  (working copy: $WC)"
svn status "$WC" | sed 's/^/   /'
[ -z "$DIFF" ] && echo "trunk matches dev source: OK" || { echo "trunk differs from dev source:"; echo "$DIFF"; exit 1; }
[ -z "$UNVERSIONED" ] || { echo "Unexpected unversioned files:"; echo "$UNVERSIONED"; exit 1; }

if [ "$COMMIT" != "--commit" ]; then
  echo
  echo "Prepared, nothing committed. Review the list above, then re-run with --commit."
  exit 0
fi

svn commit -q "$WC/trunk" -m "Initial release $VER" --non-interactive && echo "trunk committed" || exit 1
svn commit -q "$WC/assets" -m "Add plugin icon, banners, and screenshots" --non-interactive && echo "assets committed" || exit 1
svn up -q "$WC" && svn cp -q "$WC/trunk" "$WC/tags/$VER" && svn commit -q "$WC/tags/$VER" -m "Tag $VER" --non-interactive && echo "tags/$VER committed" || exit 1
echo "Published. Check https://wordpress.org/plugins/$SLUG/ in a few minutes, then: submission-watch.sh --published $SLUG"
