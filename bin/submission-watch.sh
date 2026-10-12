#!/usr/bin/env bash
#
# Drives the one-plugin-at-a-time WP.org submission pipeline from dev-tools/submission-queue.txt.
#
# WP.org allows only one plugin in review per account, so the pipeline is a queue:
#   queued -> ready (preflight passed, zip built) -> in-review (YOU clicked Submit)
#          -> approved (WP.org created its SVN repo) -> published (first SVN release done)
#
# Approval signal: WP.org creates https://plugins.svn.wordpress.org/<slug>/ only when a plugin
# is approved (404 before, 200 after) -- public, no login needed.
#
# This script NEVER submits anything to WP.org. The "Add your plugin" form is submitted under
# the owner's own WP.org account and agrees to the guidelines in their name, so that one click
# always stays a human step. Everything before and after it is automated here.
#
# Usage:
#   submission-watch.sh                 # check in-review plugin; if approved, prepare the next one
#   submission-watch.sh --status        # print the queue
#   submission-watch.sh --submitted <slug>   # record that you submitted <slug> (ready -> in-review)
#   submission-watch.sh --published <slug>   # record that the first SVN release is done
#
# Exit codes (for schedulers): 0 = nothing new, 10 = approved + next plugin READY to submit,
#   11 = approved but next plugin FAILED preflight, 12 = a plugin is ready and waiting for you
#   to submit it, 2 = usage/queue error.

set -u
TOOLS="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE="$TOOLS/submission-queue.txt"
ROOT="$(cd "$TOOLS/.." && pwd)"
TODAY=$(date +%F)

[ -f "$QUEUE" ] || { echo "Queue file missing: $QUEUE"; exit 2; }

set_status() {  # set_status <slug> <status>
  local tmp; tmp=$(mktemp)
  awk -v s="$1" -v st="$2" -v d="$TODAY" '!/^#/ && $1==s {print s" "st" "d; next} {print}' "$QUEUE" > "$tmp" && cat "$tmp" > "$QUEUE"
  rm -f "$tmp"
  grep -q "^$1 $2 " "$QUEUE" || { echo "Failed to update $1 in queue"; exit 2; }
}
first_with() { awk -v st="$1" '!/^#/ && $2==st {print $1; exit}' "$QUEUE"; }

case "${1:-}" in
  --status)
    awk '!/^#/ && NF {c[$2]++} END {for (k in c) printf "%s=%d  ", k, c[k]; print ""}' "$QUEUE"
    grep -vE '^#|queued' "$QUEUE"
    echo "next queued: $(first_with queued)"
    exit 0 ;;
  --submitted)
    S="${2:?--submitted <slug>}"
    grep -qE "^$S (ready|queued)" "$QUEUE" || { echo "$S is not ready/queued in the queue"; exit 2; }
    [ -z "$(first_with in-review)" ] || { echo "$(first_with in-review) is still in review -- WP.org allows one at a time"; exit 2; }
    set_status "$S" in-review; echo "Recorded: $S in-review since $TODAY"; exit 0 ;;
  --published)
    S="${2:?--published <slug>}"
    grep -qE "^$S approved" "$QUEUE" || { echo "$S is not 'approved' in the queue"; exit 2; }
    set_status "$S" published; echo "Recorded: $S published"; exit 0 ;;
  "") ;;
  *) echo "Unknown option $1"; exit 2 ;;
esac

REVIEW=$(first_with in-review)
READY=$(first_with ready)

if [ -n "$REVIEW" ]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://plugins.svn.wordpress.org/$REVIEW/")
  if [ "$CODE" != 200 ]; then
    echo "WAITING: $REVIEW still in review (SVN repo: HTTP $CODE). Nothing to do."
    exit 0
  fi
  set_status "$REVIEW" approved
  echo "APPROVED: $REVIEW -- WP.org created its SVN repo. First publish: dev-tools/bin/svn-first-publish.sh $REVIEW"
elif [ -n "$READY" ]; then
  echo "WAITING FOR YOU: $READY is ready -- upload wp-org-submission-zips/$READY.zip at https://wordpress.org/plugins/developers/add/ then run: submission-watch.sh --submitted $READY"
  exit 12
fi

# Nothing in review and nothing ready: prepare the next queued plugin.
NEXT=$(first_with queued)
[ -n "$NEXT" ] || { echo "Queue empty -- every plugin has been submitted."; exit 0; }

echo
if bash "$TOOLS/bin/preflight.sh" "$NEXT"; then
  set_status "$NEXT" ready
  echo
  echo "NEXT READY: $NEXT -- upload $ROOT/wp-org-submission-zips/$NEXT.zip at https://wordpress.org/plugins/developers/add/, click Submit, then run: submission-watch.sh --submitted $NEXT"
  exit 10
fi
echo
echo "NEXT BLOCKED: $NEXT failed preflight -- fix the FAIL lines above, then re-run."
exit 11
