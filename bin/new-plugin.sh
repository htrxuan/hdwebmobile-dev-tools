#!/usr/bin/env bash
#
# Scaffold a new hdwebmobile-* plugin: bootstrap, activator, core, admin, hub file (cloned
# from the freshest existing plugin so its Overview list is always current), readme.txt,
# README.md, .gitignore, languages/index.php -- then registers the new plugin's tab in every
# sibling plugin's hub Overview list via sync-overview.py.
#
# Usage:
#   new-plugin.sh <slug> "<Display Name>" <PREFIX> <ns> "<one-line description>"
#
# Example:
#   new-plugin.sh hdwebmobile-foo-bar "HDWebmobile Foo Bar" HDFB hdfb \
#     "Does foo bar things -- closed by construction against CVE-XXXX-YYYYY."
#
# What it does NOT do (deliberately -- these stay manual, reviewed steps):
#   - write the actual feature code (repository/frontend/etc. classes)
#   - git init / GitHub repo creation (do that once the plugin is feature-complete and
#     tested, so the first commit is real code, not bare boilerplate)
#   - build a submission zip or run Plugin Check (run those after you've written the code)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$(dirname "$DEV_TOOLS_DIR")/wp-content/plugins"
TEMPLATES_DIR="$DEV_TOOLS_DIR/templates"

usage() {
    echo "Usage: $0 <slug> \"<Display Name>\" <PREFIX> <ns> \"<one-line description>\"" >&2
    echo "  slug:   hdwebmobile-foo-bar  (lowercase, hyphens, must start with hdwebmobile-)" >&2
    echo "  PREFIX: HDFB                 (uppercase, used as HDFB_VERSION, HDFB_Core, ...)" >&2
    echo "  ns:     hdfb                 (lowercase, used as namespace htrxuan\\hdfb and in filenames)" >&2
    exit 1
}

[ $# -eq 5 ] || usage

SLUG="$1"
NAME="$2"
PREFIX="$3"
NS="$4"
DESC="$5"

# --- validate ---------------------------------------------------------------

if [[ ! "$SLUG" =~ ^hdwebmobile-[a-z0-9-]+$ ]]; then
    echo "ERROR: slug must match ^hdwebmobile-[a-z0-9-]+$, got: $SLUG" >&2
    exit 1
fi
if [[ ! "$PREFIX" =~ ^HD[A-Z0-9]+$ ]]; then
    echo "ERROR: PREFIX must match ^HD[A-Z0-9]+$, got: $PREFIX" >&2
    exit 1
fi
if [[ ! "$NS" =~ ^hd[a-z0-9]+$ ]]; then
    echo "ERROR: ns must match ^hd[a-z0-9]+$, got: $NS" >&2
    exit 1
fi

TARGET_DIR="$PLUGINS_DIR/$SLUG"
if [ -e "$TARGET_DIR" ]; then
    echo "ERROR: $TARGET_DIR already exists -- pick a different slug or remove it first." >&2
    exit 1
fi

# Prefix/namespace must not collide with any existing plugin.
if grep -rlq "define('${PREFIX}_VERSION'" "$PLUGINS_DIR"/*/*.php 2>/dev/null; then
    echo "ERROR: prefix ${PREFIX} is already used by an existing plugin:" >&2
    grep -rl "define('${PREFIX}_VERSION'" "$PLUGINS_DIR"/*/*.php 2>/dev/null >&2
    exit 1
fi
if grep -rlq "namespace htrxuan\\\\${NS};" "$PLUGINS_DIR"/*/*.php "$PLUGINS_DIR"/*/includes/*.php 2>/dev/null; then
    echo "ERROR: namespace htrxuan\\${NS} is already used by an existing plugin:" >&2
    grep -rl "namespace htrxuan\\\\${NS};" "$PLUGINS_DIR"/*/*.php "$PLUGINS_DIR"/*/includes/*.php 2>/dev/null >&2
    exit 1
fi

# The hub tab key: the slug with the "hdwebmobile-" prefix stripped (matches the convention
# used by every existing plugin's register_hub_tabs(), e.g. 'checkout-delivery-scheduler').
TABKEY="${SLUG#hdwebmobile-}"

# A short display name for the tab label / stub content: the display name with any leading
# "HDWebmobile " stripped (matches e.g. "Checkout Delivery Scheduler" for the tab label of
# "HDWebmobile Checkout Delivery Scheduler").
NAME_SHORT="${NAME#HDWebmobile }"

# Pick a hub-tab 'order' one higher than the current maximum across all plugins, so the new
# tab lands at the end of the tab bar by default (reorder later by hand if you want it
# grouped near a related plugin).
MAX_ORDER=$(grep -rhoE "'order'\s*=>\s*[0-9]+" "$PLUGINS_DIR"/*/includes/class-*-admin*.php 2>/dev/null \
    | grep -oE '[0-9]+' | sort -n | tail -1)
MAX_ORDER=${MAX_ORDER:-0}
NEW_ORDER=$((MAX_ORDER + 2))

echo "Scaffolding $SLUG ($PREFIX / htrxuan\\$NS) -> $TARGET_DIR"
echo "  tab key: $TABKEY   tab order: $NEW_ORDER"

# --- render a template: substitute placeholders, write to destination -------

render() {
    local template="$1" dest="$2"
    # Escape sed's special replacement characters in free-text values (backslash first, so
    # the escapes just inserted aren't themselves re-escaped by a later step).
    local desc_escaped="$DESC"
    desc_escaped="${desc_escaped//\\/\\\\}"
    desc_escaped="${desc_escaped//\//\\/}"
    desc_escaped="${desc_escaped//&/\\&}"
    sed \
        -e "s/__SLUG__/${SLUG}/g" \
        -e "s/__NAME_SHORT__/${NAME_SHORT}/g" \
        -e "s/__NAME__/${NAME}/g" \
        -e "s/__PREFIX__/${PREFIX}/g" \
        -e "s/__NS__/${NS}/g" \
        -e "s/__TABKEY__/${TABKEY}/g" \
        -e "s/__ORDER__/${NEW_ORDER}/g" \
        -e "s/__DESC__/${desc_escaped}/g" \
        "$template" > "$dest"
}
# NAME_SHORT must be substituted before NAME (it's a substring of it), and TABKEY/ORDER are
# plain tokens with no risk of colliding with the others -- order above matters.

mkdir -p "$TARGET_DIR/includes" "$TARGET_DIR/languages" "$TARGET_DIR/assets"

render "$TEMPLATES_DIR/bootstrap.php.tmpl"        "$TARGET_DIR/$SLUG.php"
render "$TEMPLATES_DIR/activator.php.tmpl"        "$TARGET_DIR/includes/class-${NS}-activator.php"
render "$TEMPLATES_DIR/core.php.tmpl"             "$TARGET_DIR/includes/class-${NS}-core.php"
render "$TEMPLATES_DIR/admin.php.tmpl"            "$TARGET_DIR/includes/class-${NS}-admin.php"
render "$TEMPLATES_DIR/readme.txt.tmpl"           "$TARGET_DIR/readme.txt"
render "$TEMPLATES_DIR/README.md.tmpl"            "$TARGET_DIR/README.md"
render "$TEMPLATES_DIR/gitignore.tmpl"            "$TARGET_DIR/.gitignore"
render "$TEMPLATES_DIR/languages-index.php.tmpl"  "$TARGET_DIR/languages/index.php"

# The hub file is NOT a static template -- it's cloned from whichever existing plugin's hub
# file was modified most recently, so its Overview list is always the current one rather than
# a copy baked into this tool that would go stale the moment a 36th plugin is scaffolded.
SOURCE_HUB=$(ls -t "$PLUGINS_DIR"/*/includes/class-*-hub.php 2>/dev/null | head -1)
if [ -z "$SOURCE_HUB" ]; then
    echo "ERROR: no existing includes/class-*-hub.php found to clone from." >&2
    exit 1
fi
SOURCE_NS=$(grep -m1 -oE 'namespace htrxuan\\[a-z0-9]+;' "$SOURCE_HUB" | sed -E 's/namespace htrxuan\\([a-z0-9]+);/\1/')
SOURCE_CLASS=$(grep -m1 -oE 'final class [A-Z0-9_]+_Hub' "$SOURCE_HUB" | awk '{print $3}')
if [ -z "$SOURCE_NS" ] || [ -z "$SOURCE_CLASS" ]; then
    echo "ERROR: could not parse namespace/class out of $SOURCE_HUB -- aborting so nothing half-broken is left behind." >&2
    exit 1
fi
echo "  cloning hub file from: $SOURCE_HUB (namespace htrxuan\\$SOURCE_NS, class $SOURCE_CLASS)"
sed \
    -e "s/namespace htrxuan\\\\${SOURCE_NS};/namespace htrxuan\\\\${NS};/" \
    -e "s/${SOURCE_CLASS}/${PREFIX}_Hub/g" \
    "$SOURCE_HUB" > "$TARGET_DIR/includes/class-${NS}-hub.php"

php -l "$TARGET_DIR/includes/class-${NS}-hub.php" >/dev/null

echo "  files written:"
find "$TARGET_DIR" -type f | sed 's/^/    /'

# --- register the new plugin's own tab in every hub file's Overview list, including its own
SYNC="$SCRIPT_DIR/sync-overview.py"
if [ -x "$SYNC" ] || [ -f "$SYNC" ]; then
    echo
    echo "Registering $SLUG in every plugin's Overview list..."
    python3 "$SYNC" --plugins-dir "$PLUGINS_DIR" --slug "$SLUG" --file "$SLUG.php" \
        --name "$NAME_SHORT" --desc "$DESC"
else
    echo "WARNING: sync-overview.py not found next to this script -- the new plugin was NOT" >&2
    echo "added to any Overview list. Run it manually once it's available." >&2
fi

cat <<EOF

Done. Next steps (manual, on purpose):
  1. Write the real feature code (repository/frontend/admin classes) in $TARGET_DIR/includes/.
  2. Fill in readme.txt / README.md's TODO sections (the CVE + closed-by-construction story).
  3. Adjust the tab 'order' in includes/class-${NS}-admin.php if $NEW_ORDER isn't where you want it.
  4. Copy dev-tools/templates/test-harness.php.tmpl to a scratch test-${NS}.php and write real cases.
  5. php -l every file, wp plugin activate $SLUG, wp plugin check $SLUG.
  6. Browser-test, then: git init, first commit, gh repo create htrxuan/$SLUG --public --push.
  7. dev-tools/bin/build-zips.sh $SLUG
EOF
