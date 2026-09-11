#!/usr/bin/env python3
"""
Register a plugin's tab in the Overview `$plugins = array(...)` list carried by every
includes/class-*-hub.php file across the suite, inserting it at the correct alphabetical
position (case-insensitive, by 'name') rather than requiring a human to reason about where
'Coupon Links' sorts against 'Currency Switcher' by hand every time.

Idempotent: a hub file that already references the given --file path is left untouched, so
running this twice (or as part of new-plugin.sh, which already calls it once) never
duplicates an entry.

Deliberately conservative: a hub file whose Overview list this script can't confidently parse
(zero recognisable `array('name' => ...)` entry lines) is SKIPPED with a warning rather than
guessed at -- see the three non-hub plugins (Live Shopping with Agora, Media Folder Roles,
Socials Floating), which carry a differently-shaped sibling-plugins panel this tool
intentionally does not touch.

Usage:
    sync-overview.py --plugins-dir <path/to/wp-content/plugins> \\
        --slug hdwebmobile-foo-bar --file hdwebmobile-foo-bar.php \\
        --name "Foo Bar" --desc "Does foo bar -- closed by construction against CVE-XXXX."

    sync-overview.py --plugins-dir ... --remove-slug hdwebmobile-foo-bar
        (reverts: removes any entry whose 'file' starts with "hdwebmobile-foo-bar/" --
         used by the test suite to clean up after itself; not part of normal workflow.)
"""
import argparse
import glob
import os
import re
import sys

ENTRY_RE = re.compile(
    r"^(?P<indent>[ \t]*)array\(\s*'name'\s*=>\s*'(?P<name>(?:[^'\\]|\\.)*)'.*\),\s*$"
)


def php_escape(s):
    return s.replace('\\', '\\\\').replace("'", "\\'")


def php_unescape(s):
    return s.replace("\\'", "'").replace('\\\\', '\\')


def find_hub_files(plugins_dir):
    return sorted(glob.glob(os.path.join(plugins_dir, 'hdwebmobile-*', 'includes', 'class-*-hub.php')))


def sync_one_file(path, slug, file_rel, name, desc, dry_run=False):
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()

    file_marker = f"'{slug}/{file_rel}'"
    joined = ''.join(lines)
    if file_marker in joined:
        return 'already-present'

    entries = []  # (line_index, indent, name)
    for i, line in enumerate(lines):
        m = ENTRY_RE.match(line.rstrip('\n'))
        if m:
            entries.append((i, m.group('indent'), php_unescape(m.group('name'))))

    if not entries:
        return 'no-entries-found'

    indent = entries[0][1]
    new_entry_name = php_escape(name)
    new_entry_desc = php_escape(desc)
    new_line = (
        f"{indent}array('name' => '{new_entry_name}', "
        f"'file' => '{slug}/{file_rel}', "
        f"'description' => '{new_entry_desc}'),\n"
    )

    insert_at = None
    for line_index, _indent, entry_name in entries:
        if name.casefold() < entry_name.casefold():
            insert_at = line_index
            break
    if insert_at is None:
        # Sorts after every existing entry: insert right after the last one.
        insert_at = entries[-1][0] + 1

    if dry_run:
        return f'would-insert-at-line-{insert_at + 1}'

    lines.insert(insert_at, new_line)
    with open(path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    return f'inserted-at-line-{insert_at + 1}'


def remove_one_file(path, slug, dry_run=False):
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()

    prefix_marker = f"'file' => '{slug}/"
    kept = [ln for ln in lines if prefix_marker not in ln]
    if len(kept) == len(lines):
        return 'not-present'
    if dry_run:
        return f'would-remove-{len(lines) - len(kept)}-line(s)'
    with open(path, 'w', encoding='utf-8') as f:
        f.writelines(kept)
    return f'removed-{len(lines) - len(kept)}-line(s)'


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--plugins-dir', required=True, help='Path to wp-content/plugins')
    p.add_argument('--slug', help='Plugin directory slug, e.g. hdwebmobile-foo-bar')
    p.add_argument('--file', help='Bootstrap filename relative to the plugin dir, e.g. hdwebmobile-foo-bar.php')
    p.add_argument('--name', help='Display name for the Overview entry, e.g. "Foo Bar"')
    p.add_argument('--desc', help='One-sentence description for the Overview entry')
    p.add_argument('--remove-slug', help='Instead of inserting, remove any entry whose file starts with SLUG/')
    p.add_argument('--dry-run', action='store_true', help='Report what would change without writing anything')
    args = p.parse_args()

    if not args.remove_slug and not (args.slug and args.file and args.name and args.desc):
        p.error('either --remove-slug, or all of --slug/--file/--name/--desc, are required')

    hub_files = find_hub_files(args.plugins_dir)
    if not hub_files:
        print(f'No includes/class-*-hub.php files found under {args.plugins_dir}', file=sys.stderr)
        sys.exit(1)

    counts = {}
    for path in hub_files:
        rel = os.path.relpath(path, args.plugins_dir)
        if args.remove_slug:
            result = remove_one_file(path, args.remove_slug, dry_run=args.dry_run)
        else:
            result = sync_one_file(path, args.slug, args.file, args.name, args.desc, dry_run=args.dry_run)
        counts[result] = counts.get(result, 0) + 1
        marker = '·' if result in ('already-present', 'not-present') else '✓'
        print(f'  {marker} {rel}: {result}')

    print()
    print('Summary: ' + ', '.join(f'{v} {k}' for k, v in sorted(counts.items())))

    if counts.get('no-entries-found'):
        print(
            'WARNING: some hub files had no parseable Overview entries and were left '
            'untouched -- check them manually (this is expected for the 3 non-hub plugins '
            'that carry a differently-shaped sibling-plugins panel instead: Live Shopping '
            'with Agora, Media Folder Roles, Socials Floating).',
            file=sys.stderr,
        )


if __name__ == '__main__':
    main()
