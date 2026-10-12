#!/usr/bin/env bash
#
# Pre-submission checklist for one hdwebmobile-* plugin -- every check that has cost a real
# WP.org review round in this project, run before a zip is ever uploaded:
#
#   1. Folder slug == sanitize_title(Plugin Name) == Text Domain   (Product Options rejection)
#   2. Every translation call uses that same text domain           (Delivery Date rejection)
#   3. Version header == readme Stable tag; Tested up to is current
#   4. Readme short description <= 150 chars
#   5. Readme names no other plugins / CVE ids                     (Wishlist pre-review flag)
#   6. Any remote call or external script => "== External services ==" section in readme
#   7. Every admin_notices callback is screen-scoped               (Loyalty Points Guideline 11)
#   8. No class_exists()/function_exists() guard around our OWN symbols (Shipment Tracking rejection)
#   9. `wp plugin check` clean (ignoring hidden_files from the local .git)
#  10. Plugin URI on hdwebmobile.com answers 200                   (Shipment Tracking rejection)
#  11. Git working tree clean and pushed
#  12. Fresh zip builds, top folder == slug, no dev files inside
#
# Usage: preflight.sh <slug>          e.g. preflight.sh hdwebmobile-order-bump
# Exit status: 0 = ready to submit, 1 = at least one FAIL.

set -u
SLUG="${1:?usage: preflight.sh <slug>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"          # .../dev-plugins
P="$ROOT/wp-content/plugins/$SLUG"
ZIPDIR="$ROOT/wp-org-submission-zips"
MAIN="$P/$SLUG.php"
README="$P/readme.txt"
FAILS=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
warn() { printf '  WARN  %s\n' "$1"; }

[ -d "$P" ] || { echo "No such plugin: $P"; exit 1; }
[ -f "$MAIN" ] || { echo "Main file $SLUG.php not found"; exit 1; }
echo "Preflight: $SLUG"

# --- 1-4: header / readme metadata (via WordPress's own sanitize_title + get_plugin_data) ---
META="$(cd "$ROOT" && PF_MAIN="$MAIN" wp eval '
$f = getenv("PF_MAIN"); $h = get_plugin_data($f, false, false);
echo sanitize_title($h["Name"]), "\n", $h["TextDomain"], "\n", $h["Version"], "\n", $h["PluginURI"], "\n";
echo implode(".", array_slice(explode(".", get_bloginfo("version")), 0, 2)), "\n";
' 2>/dev/null)"
[ -n "$META" ] || { echo "Could not read plugin headers via wp eval (is WP-CLI working in $ROOT?)"; exit 1; }
NAME_SLUG=$(sed -n 1p <<<"$META"); TD=$(sed -n 2p <<<"$META"); VER=$(sed -n 3p <<<"$META")
URI=$(sed -n 4p <<<"$META"); WPVER=$(sed -n 5p <<<"$META")

[ "$NAME_SLUG" = "$SLUG" ] && pass "sanitize_title(Plugin Name) = $SLUG" \
  || fail "Plugin Name gives slug '$NAME_SLUG', folder is '$SLUG' (WP.org assigns the former)"
[ "$TD" = "$SLUG" ] && pass "Text Domain = $SLUG" || fail "Text Domain is '$TD', expected '$SLUG'"

BAD_TD=$(grep -rhoE "(__|_e|_x|_ex|_n|_nx|esc_html__|esc_html_e|esc_html_x|esc_attr__|esc_attr_e|esc_attr_x)\([^;]*['\"]hdwebmobile-[a-z0-9-]+['\"]\s*\)" "$P" --include='*.php' \
  | grep -oE "['\"]hdwebmobile-[a-z0-9-]+['\"]\s*\)$" | tr -d "'\") " | sort -u | grep -vx "$SLUG")
[ -z "$BAD_TD" ] && pass "all translation calls use '$SLUG'" || fail "translation calls with other domains: $(echo $BAD_TD)"

STABLE=$(grep -m1 -i '^Stable tag:' "$README" | sed 's/.*: *//' | tr -d '\r ')
TESTED=$(grep -m1 -i '^Tested up to:' "$README" | sed 's/.*: *//' | tr -d '\r ')
[ "$STABLE" = "$VER" ] && pass "Stable tag = Version = $VER" || fail "Stable tag '$STABLE' != Version '$VER'"
if [ -n "$WPVER" ] && printf '%s\n%s\n' "$WPVER" "$TESTED" | sort -V -C; then
  pass "Tested up to $TESTED (WordPress is $WPVER)"
else
  fail "Tested up to '$TESTED' is older than current WordPress $WPVER"
fi

SHORT=$(awk 'BEGIN{h=1} /^===/{next} h && /^[A-Za-z ]+:/{next} h && NF==0{if(seen)exit; next} {h=0; seen=1; print; exit}' "$README")
LEN=${#SHORT}
[ "$LEN" -gt 0 ] && [ "$LEN" -le 150 ] && pass "short description $LEN chars" || fail "short description is $LEN chars (must be 1-150)"

# --- 5: readme wording ---
HITS=$(grep -nE "CVE-[0-9]|[Cc]ompeting|[Cc]ompetitor|unlike (other|most)" "$README" | cut -c1-90)
[ -z "$HITS" ] && pass "readme names no other plugins / CVEs" || fail "readme comparative/CVE wording:"$'\n'"$(sed 's/^/          /' <<<"$HITS")"

# --- 6: external services disclosure ---
EXT=$(grep -rlE "wp_remote_(get|post|request)|wp_safe_remote_|curl_init|wp_enqueue_script\([^)]*['\"]https?://" "$P" --include='*.php' | sed "s#$P/##")
if [ -n "$EXT" ]; then
  grep -q '^== External services ==' "$README" && pass "external calls disclosed in readme" \
    || fail "remote calls/scripts in $(echo $EXT) but no '== External services ==' readme section"
else
  pass "no remote calls or external scripts"
fi

# --- 7: admin_notices scoping ---
UNSCOPED=""
for f in $(grep -rl "add_action('admin_notices'" "$P" --include='*.php'); do
  for fn in $(grep -oE "add_action\('admin_notices', array\(\\\$this, '[a-z_]+'" "$f" | sed -E "s/.*'([a-z_]+)'$/\1/"); do
    awk "/function $fn\(/,/^    }/" "$f" | grep -qE "get_current_screen|\\\$_GET\['(page|tab)'\]|pagenow" || UNSCOPED+=" ${f#$P/}::$fn"
  done
done
[ -z "$UNSCOPED" ] && pass "admin notices are screen-scoped" || fail "unscoped admin_notices callbacks:$UNSCOPED"

# --- 8: exists-guards around our own symbols ---
GUARDS=$(grep -rnE "(class|function)_exists\(\s*['\"](HD|hd|htrxuan)" "$P" --include='*.php' | cut -c1-110)
[ -z "$GUARDS" ] && pass "no exists-guards around own classes/functions" || fail "exists-guard on own symbol:"$'\n'"$(sed 's/^/          /' <<<"$GUARDS")"

# --- 9: Plugin Check ---
PC=$(cd "$ROOT" && wp plugin check "$SLUG" --format=csv 2>/dev/null | tail -n +2 | grep -v hidden_files | grep -v '^line,' | grep .)
[ -z "$PC" ] && pass "wp plugin check clean" || fail "wp plugin check:"$'\n'"$(head -8 <<<"$PC" | cut -c1-160 | sed 's/^/          /')"

# --- 10: Plugin URI ---
CODE=$([ -n "$URI" ] && curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$URI" || echo "no Plugin URI header")
[ "$CODE" = 200 ] && pass "Plugin URI $URI -> 200" || fail "Plugin URI $URI -> $CODE"

# --- 11: git state ---
if git -C "$P" rev-parse >/dev/null 2>&1; then
  DIRTY=$(git -C "$P" status --porcelain | wc -l | tr -d ' ')
  AHEAD=$(git -C "$P" status -sb | head -1 | grep -o 'ahead [0-9]*')
  [ "$DIRTY" = 0 ] && [ -z "$AHEAD" ] && pass "git clean and pushed" || fail "git: $DIRTY uncommitted file(s) ${AHEAD:+, $AHEAD}"
else
  warn "not a git repo"
fi

# --- 12: zip ---
bash "$ROOT/dev-tools/bin/build-zips.sh" "$SLUG" >/dev/null 2>&1
Z="$ZIPDIR/$SLUG.zip"
if [ -f "$Z" ]; then
  TOP=$(unzip -Z1 "$Z" | cut -d/ -f1 | sort -u)
  JUNK=$(unzip -Z1 "$Z" | grep -E '(^|/)(\.git|\.gitignore|README\.md|LICENSE|\.DS_Store|node_modules|package(-lock)?\.json)(/|$)|\.py$' | head -5)
  [ "$TOP" = "$SLUG" ] && [ -z "$JUNK" ] && pass "zip built: $Z" || fail "zip problem (top folder: $TOP; dev files: $(echo $JUNK))"
else
  fail "zip was not built"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "READY: $SLUG passes all checks"; exit 0; fi
echo "NOT READY: $FAILS check(s) failed"; exit 1
