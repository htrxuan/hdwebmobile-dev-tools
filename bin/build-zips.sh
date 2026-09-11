#!/usr/bin/env bash
#
# Build (or rebuild) WP.org submission zips, excluding the files that never belong in one:
# .git/*, .gitignore, LICENSE, README.md, assets/*.png, .DS_Store.
#
# Usage:
#   build-zips.sh                    # rebuild every hdwebmobile-* plugin's zip
#   build-zips.sh <slug> [<slug> ...] # rebuild just the given plugin(s)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
DEV_PLUGINS_DIR="$(dirname "$DEV_TOOLS_DIR")"
PLUGINS_DIR="$DEV_PLUGINS_DIR/wp-content/plugins"
ZIP_DIR="$DEV_PLUGINS_DIR/wp-org-submission-zips"

mkdir -p "$ZIP_DIR"

if [ $# -gt 0 ]; then
    SLUGS=("$@")
else
    SLUGS=()
    for d in "$PLUGINS_DIR"/hdwebmobile-*/; do
        SLUGS+=("$(basename "$d")")
    done
fi

BUILT=0
for slug in "${SLUGS[@]}"; do
    dir="$PLUGINS_DIR/$slug"
    if [ ! -d "$dir" ]; then
        echo "SKIP (no such plugin directory): $slug" >&2
        continue
    fi
    zip_path="$ZIP_DIR/$slug.zip"
    rm -f "$zip_path"
    (cd "$PLUGINS_DIR" && zip -rq "$zip_path" "$slug" \
        -x "*/.git/*" "*/.gitignore" "*/LICENSE" "*/README.md" "$slug/assets/*.png" "*/.DS_Store")
    size=$(du -h "$zip_path" | cut -f1)
    echo "built $slug.zip ($size)"
    BUILT=$((BUILT + 1))
done

echo
echo "Built $BUILT zip(s) in $ZIP_DIR"
