#!/usr/bin/env bash
#
# Update release of an already-published plugin on WP.org SVN: sync trunk/ to the git-tracked
# dev source, show what changed, then STOP unless --commit is given.
#
# Same rules as svn-first-publish.sh (copy only `git ls-files`, minus repo-only files and
# marketing images; verify trunk is identical to the dev source), plus: files removed from git
# are `svn rm`'d from trunk, and assets/ is left alone (update those separately when needed).
#
# Usage:
#   svn-release.sh <slug>            # prepare + show changes, commit nothing
#   svn-release.sh <slug> --commit   # also commit trunk and tags/<version>

set -u
SLUG="${1:?usage: svn-release.sh <slug> [--commit]}"
COMMIT="${2:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/wp-content/plugins/$SLUG"
WC="/Volumes/www/svn/$SLUG"
URL="https://plugins.svn.wordpress.org/$SLUG"
EXCL='^(\.gitignore|README\.md|LICENSE)$|^assets/[^/]+\.(png|jpe?g|gif)$|^assets/icon\.svg$'

[ -d "$SRC/.git" ] || { echo "No git repo at $SRC"; exit 1; }
[ -z "$(git -C "$SRC" status --porcelain)" ] || { echo "Dev source has uncommitted changes -- commit them first"; exit 1; }

VER=$(grep -m1 -E '^\s*\*\s*Version:' "$SRC/$SLUG.php" | sed 's/.*Version:\s*//' | tr -d ' \r')
STABLE=$(grep -m1 -E '^Stable tag:' "$SRC/readme.txt" | sed 's/Stable tag:\s*//' | tr -d ' \r')
[ -n "$VER" ] && [ "$VER" = "$STABLE" ] || { echo "Version ($VER) and Stable tag ($STABLE) differ"; exit 1; }

if [ -d "$WC/.svn" ]; then svn up -q "$WC"; else svn co -q "$URL" "$WC"; fi || { echo "svn checkout/update failed"; exit 1; }
[ -d "$WC/trunk" ] || { echo "No trunk/ in $URL -- use svn-first-publish.sh"; exit 1; }
[ -e "$WC/tags/$VER" ] && { echo "tags/$VER already exists in SVN -- bump the version first"; exit 1; }

TRACKED=$(git -C "$SRC" ls-files | grep -vE "$EXCL")

# Remove from trunk anything no longer tracked in git.
( cd "$WC/trunk" && svn ls -R . | grep -v '/$' ) | while read -r f; do
  echo "$TRACKED" | grep -qxF "$f" || svn rm -q "$WC/trunk/$f"
done
# Copy every tracked file in.
echo "$TRACKED" | while read -r f; do
  mkdir -p "$WC/trunk/$(dirname "$f")"
  cp "$SRC/$f" "$WC/trunk/$f"
done
svn add -q --force "$WC/trunk"

DIFF=$(diff -rq -x .svn -x .git -x .gitignore -x README.md -x LICENSE -x .DS_Store -x assets "$WC/trunk" "$SRC" 2>&1 | grep -v '^Only in '"$SRC"': assets$' |
  while read -r line; do
    # Empty dev-only directories (git can't track them) are not a real difference.
    if [[ "$line" =~ ^Only\ in\ (.*):\ (.*)$ ]] && [ -d "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" ] && [ -z "$(ls -A "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}")" ]; then continue; fi
    echo "$line"
  done)
UNVERSIONED=$(svn status "$WC/trunk" | grep '^?')
echo "== $SLUG $VER  (working copy: $WC)"
svn status "$WC/trunk" | sed 's/^/   /'
[ -z "$DIFF" ] && echo "trunk matches dev source: OK" || { echo "trunk differs from dev source:"; echo "$DIFF"; exit 1; }
[ -z "$UNVERSIONED" ] || { echo "Unexpected unversioned files:"; echo "$UNVERSIONED"; exit 1; }

if [ "$COMMIT" != "--commit" ]; then
  echo "Prepared, nothing committed. Re-run with --commit to release $VER."
  exit 0
fi

svn commit -q "$WC/trunk" -m "Release $VER" --non-interactive && echo "trunk committed" || exit 1
svn up -q "$WC" && svn cp -q "$WC/trunk" "$WC/tags/$VER" && svn commit -q "$WC/tags/$VER" -m "Tag $VER" --non-interactive && echo "tags/$VER committed" || exit 1
echo "Released $VER. Check https://wordpress.org/plugins/$SLUG/ in a few minutes."
