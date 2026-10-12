# hdwebmobile dev-tools

Small, in-house scripts for the `hdwebmobile-*` WooCommerce plugin suite. Not a WordPress
plugin, not published anywhere -- this is scaffolding/automation for the person (or agent)
building the suite, kept as real files in a real repo so it survives session restarts instead
of being re-derived from scratch in a scratchpad every time.

Why this exists instead of an external framework: every plugin in this suite follows the same
proven shape (bootstrap → activator → core → admin → shared hub tab → readme/README →
GitHub → WP.org zip), and the actual repeated failure modes have been mechanical --
re-typing near-identical boilerplate, reasoning by hand about where a new entry sorts
alphabetically across 30+ files, forgetting that some sibling repos are on `main` and others
on `master`. These tools remove exactly those failure modes. They do **not** try to automate
the part that actually needs a person/agent thinking: picking a real CVE, designing the
closed-by-construction fix, and writing the feature code and its tests.

## `bin/new-plugin.sh`

Scaffolds a brand-new plugin: bootstrap file, activator, a minimal core + admin stub, and a
hub file cloned from whichever existing plugin's hub file was modified most recently (so its
Overview list is always current -- nothing here bakes in a stale copy of the plugin list).
Then it calls `sync-overview.py` itself to register the new plugin's own tab everywhere.

```
dev-tools/bin/new-plugin.sh hdwebmobile-foo-bar "HDWebmobile Foo Bar" HDFB hdfb \
  "Does foo bar things -- closed by construction against CVE-XXXX-YYYYY."
```

Validates: slug/prefix/namespace shape, and that the prefix and namespace aren't already used
by an existing plugin (refuses to scaffold a collision). Does **not** `git init`, create a
GitHub repo, or build a zip -- those stay manual, deliberate steps done once the plugin
actually has real feature code in it, not at scaffold time.

## `bin/sync-overview.py`

Inserts one plugin's entry into the `$plugins = array(...)` Overview list of every
`includes/class-*-hub.php` file across the suite, at the correct case-insensitive
alphabetical position -- no more comparing letter codes by hand to decide where "Coupon
Links" sorts against "Currency Switcher". Idempotent (skips a file that already has the
entry); conservative (skips, with a warning, any hub file it can't confidently parse, rather
than guessing).

```
python3 dev-tools/bin/sync-overview.py --plugins-dir /path/to/wp-content/plugins \
  --slug hdwebmobile-foo-bar --file hdwebmobile-foo-bar.php \
  --name "Foo Bar" --desc "One-sentence description for the Overview row."
```

Add `--dry-run` to see what it would do without writing anything. `--remove-slug SLUG`
reverts (used by this tool's own test suite to clean up after itself -- not part of the
normal per-plugin workflow).

**Known gap, on purpose:** three already-live plugins (Live Shopping with Agora, Media
Folder Roles, Socials Floating) carry their own differently-shaped "More WooCommerce
Plugins" panel instead of a `class-*-hub.php` file. This script does not touch them; it
reports `no-entries-found` for anything it can't parse rather than corrupting an
unfamiliar shape.

## `bin/build-zips.sh`

Rebuilds WP.org submission zips with the standard exclusions (`.git/*`, `.gitignore`,
`LICENSE`, `README.md`, `assets/*.png`, `.DS_Store`).

```
dev-tools/bin/build-zips.sh                              # every plugin
dev-tools/bin/build-zips.sh hdwebmobile-foo-bar           # just one (or list several)
```

## `bin/push-changes.sh`

Commits and pushes whatever's uncommitted in one, several, or every plugin repo, appending
the standing attribution trailer automatically and using **each repo's own current branch**
(this suite has a real mix of `main` and `master`, from whenever each repo was first
`git init`'d -- a hardcoded branch name fails silently on the other kind).

```
dev-tools/bin/push-changes.sh "Commit message" hdwebmobile-foo-bar hdwebmobile-bar-baz
dev-tools/bin/push-changes.sh --only 'includes/class-*-hub.php' "Add Foo Bar to the Overview list"
dev-tools/bin/push-changes.sh --dry-run "..."   # report only, changes nothing
```

`--only <pathspec>` restricts what gets staged to that path per repo -- use it for a
hub-sync push so an unrelated uncommitted file (a marketing PNG dropped in but never
committed, say) doesn't get silently swept into the same commit. Without `--only`, it's a
plain `git add -A` (whatever's uncommitted, same as doing it by hand).

## WP.org submission pipeline

WP.org allows one plugin in review per account, so submissions run through a queue,
`submission-queue.txt` (one `<slug> <status> [date]` per line, top = next):

```
queued -> ready -> in-review -> approved -> published
          |          ^ you click Submit, then: submission-watch.sh --submitted <slug>
          ^ preflight.sh passed, zip built
```

- **`bin/preflight.sh <slug>`** -- every check that has cost a review round before: slug ==
  `sanitize_title(Plugin Name)` == Text Domain, translation-call domains, Stable tag/Version,
  Tested up to, short-description length, no competitor/CVE wording in the readme, an
  `== External services ==` section when the code makes remote calls, screen-scoped
  `admin_notices`, no exists-guards around our own symbols, `wp plugin check`, Plugin URI 200,
  git clean + pushed, and a fresh zip with no dev files. Exit 0 = ready.
- **`bin/submission-watch.sh`** -- checks the in-review plugin; approval is detected by WP.org
  creating `https://plugins.svn.wordpress.org/<slug>/` (404 before, 200 after). On approval it
  runs preflight on the next queued plugin and marks it `ready`. `--status` prints the queue;
  `--submitted <slug>` / `--published <slug>` record the human steps. Exit codes: 0 nothing new,
  10 next is ready, 11 next failed preflight, 12 a ready plugin is waiting for you to submit.
- **`bin/svn-first-publish.sh <slug> [--commit]`** -- first SVN release of an approved plugin:
  checkout, copy exactly the git-tracked code into `trunk/` and the PNGs into `assets/`,
  verify trunk matches the dev source, then stop; `--commit` commits trunk, assets and the tag.

**Never automated:** clicking Submit on https://wordpress.org/plugins/developers/add/. That form
is submitted under the owner's own WP.org account and agrees to the guidelines in their name.

## `templates/`

Placeholder-substituted source used by `new-plugin.sh` (`__SLUG__`, `__NAME__`,
`__NAME_SHORT__`, `__PREFIX__`, `__NS__`, `__TABKEY__`, `__ORDER__`, `__DESC__`), plus
`test-harness.php.tmpl` -- copy this (don't run it as-is) when starting a new plugin's PHP
unit-test file. It bakes in two lessons paid for the hard way this session:

1. `global $P;` inside a function does not reach a `wp eval-file`-evaluated script's
   top-level variables -- use `$GLOBALS['...']` explicitly, or your pass/fail tally silently
   stays at 0 even though every individual assertion printed correctly.
2. A "does this file avoid mentioning X" check false-positives on X appearing in a comment or
   docblock -- strip comments (`preg_replace('!/\*.*?\*/!s', '', $source)`) before searching
   code for a forbidden pattern.

## Verification

Every script here was tested against this dev site before being trusted: `new-plugin.sh`
scaffolded a real throwaway plugin (activated cleanly, Plugin Check clean, hub tab rendered
in a real browser, correct alphabetical self-registration in all 33 hub files that existed at
the time); `sync-overview.py` was checked for correct alphabetical insertion both mid-list and
at the end, and for idempotency (a second run reports `already-present` everywhere, no
duplicate lines); `build-zips.sh` was run against the throwaway plugin and its zip's contents
verified against the exclusion list; `push-changes.sh` was run against an isolated local bare
repo (not any real GitHub remote) to confirm the commit-with-trailer and per-repo-branch push
actually work, plus a `--dry-run` pass against real repos to confirm `--only` correctly
excludes unrelated uncommitted files. The throwaway plugin and every hub-file change it caused
were then fully reverted (`git checkout` per file for the 32 real sibling repos, `rm -rf` for
the never-committed scaffold directory) and confirmed byte-for-byte clean afterward.
