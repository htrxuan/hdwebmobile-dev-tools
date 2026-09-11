#!/usr/bin/env bash
#
# Commit and push whatever's currently uncommitted in one, several, or every hdwebmobile-*
# plugin repo -- auto-detecting each repo's OWN current branch rather than assuming `master`
# (this suite has a mix: some repos are on `main`, some on `master`, from whenever each was
# first `git init`'d. A hardcoded branch name silently fails on the other kind with
# "src refspec ... does not match any" -- this bit a real batch push in this project before).
#
# Every commit gets the standing attribution trailer appended automatically.
#
# Usage:
#   push-changes.sh "<commit message>" [<slug> ...]        # add -A, commit, push
#   push-changes.sh --only <pathspec> "<msg>" [<slug> ...] # stage ONLY that path per repo
#   push-changes.sh --dry-run ...                          # report only, change nothing
#
# --only exists because `git add -A` sweeps up ANYTHING uncommitted in the repo, including
# things unrelated to why you're calling this script -- e.g. a marketing-asset PNG dropped in
# earlier but never committed would get silently bundled into an unrelated "add plugin X to
# the Overview list" commit. Pass --only 'includes/class-*-hub.php' for a hub-sync push to
# stage exactly (and only) that file per repo, leaving anything else exactly as uncommitted as
# it was.
#
# With no slugs given, every hdwebmobile-* directory that is a git repo with uncommitted
# changes (or changes to --only's pathspec, if given) is included. Repos with nothing to
# commit are silently skipped either way.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
DEV_PLUGINS_DIR="$(dirname "$DEV_TOOLS_DIR")"
PLUGINS_DIR="$DEV_PLUGINS_DIR/wp-content/plugins"

TRAILER="Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"

DRY_RUN=0
ONLY_PATH=""
while true; do
    case "${1:-}" in
        --dry-run) DRY_RUN=1; shift ;;
        --only) ONLY_PATH="${2:-}"; shift 2 ;;
        *) break ;;
    esac
done

if [ $# -lt 1 ]; then
    echo "Usage: $0 [--dry-run] [--only <pathspec>] \"<commit message>\" [<slug> ...]" >&2
    exit 1
fi

MSG="$1"
shift

if [ $# -gt 0 ]; then
    SLUGS=("$@")
else
    SLUGS=()
    for d in "$PLUGINS_DIR"/hdwebmobile-*/; do
        SLUGS+=("$(basename "$d")")
    done
fi

PUSHED=0
SKIPPED=0
FAILED=()

for slug in "${SLUGS[@]}"; do
    dir="$PLUGINS_DIR/$slug"
    if [ ! -d "$dir/.git" ]; then
        continue
    fi
    cd "$dir"

    if [ -n "$ONLY_PATH" ]; then
        # Only consider (and later stage) paths matching the given pathspec.
        if [ -z "$(git status --porcelain -- "$ONLY_PATH")" ]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    else
        if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain --untracked-files=normal)" ]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi

    branch="$(git rev-parse --abbrev-ref HEAD)"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[$slug] would commit on '$branch'${ONLY_PATH:+ (only: $ONLY_PATH)}:"
        if [ -n "$ONLY_PATH" ]; then
            git status --porcelain -- "$ONLY_PATH" | sed 's/^/    /'
        else
            git status --porcelain | sed 's/^/    /'
        fi
        continue
    fi

    if [ -n "$ONLY_PATH" ]; then
        git add -- "$ONLY_PATH"
    else
        git add -A
    fi
    git -c user.name=htrxuan -c user.email=htrxuan@gmail.com commit -q -m "$(printf '%s\n\n%s' "$MSG" "$TRAILER")"
    if git push -q origin "$branch" 2>/tmp/hdwebmobile-push-err.$$; then
        echo "✓ pushed $slug [$branch]"
        PUSHED=$((PUSHED + 1))
    else
        echo "✗ FAILED to push $slug [$branch]:" >&2
        sed 's/^/    /' /tmp/hdwebmobile-push-err.$$ >&2
        FAILED+=("$slug")
    fi
    rm -f /tmp/hdwebmobile-push-err.$$
done

echo
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run complete."
else
    echo "Pushed: $PUSHED   Skipped (nothing to commit / not a git repo): $SKIPPED   Failed: ${#FAILED[@]}"
    if [ ${#FAILED[@]} -gt 0 ]; then
        printf '  %s\n' "${FAILED[@]}"
        exit 1
    fi
fi
