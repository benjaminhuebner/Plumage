#!/usr/bin/env bash
# next-issue-id.sh — allocate the next free issue ID, create the issue folder
# and spec.md from _TEMPLATE.md, and print the resulting spec path.
#
# Usage:
#   scripts/next-issue-id.sh <slug>
#
# Behavior:
#   - Scans .claude/issues/**/spec.md and .claude/issues/archive/**/spec.md
#     for the highest `id:` value in frontmatter, folding in reserved IDs
#     from the .claude/issues/.allocated/ ledger.
#   - Next ID = highest + 1 (starts at 1 if no issues exist), reserved via
#     atomic mkdir of .allocated/<id> — a parallel session losing the race
#     retries one higher. Markers are permanent (a crash burns one ID).
#   - Padding = max(issueIdPadding from <bundle>/config.json, len(str(nextId))).
#   - Creates .claude/issues/<padded-id>-<slug>/spec.md from _TEMPLATE.md.
#   - Substitutes <<<ID>>>, <<<ID_PADDED>>>, <<<TITLE>>>, <<<SLUG>>>, <<<CREATED>>>.
#   - Prints the new spec path on stdout. Exits 0 on success.
#
# Exit codes:
#   0  success — new spec created, path printed to stdout
#   1  usage error or missing template
#   2  filesystem error (couldn't write spec)
#   3  collision — issue with that slug already exists (intended idempotent guard)

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <slug>" >&2
    exit 1
fi

slug="$1"
if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "error: slug must be lowercase letters, digits, and hyphens; got: $slug" >&2
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

issues_dir=".claude/issues"
archive_dir=".claude/issues/archive"
template=".claude/issues/_TEMPLATE.md"
# Resolve the project bundle by globbing `*.plumage` in cwd (the project root).
# BundleResolver guarantees exactly one per root. `! -name '.*'` excludes the
# legacy hidden `.plumage` dotfolder so a rotting dotfolder never shadows the
# real bundle. Empty glob → padding falls back to the default 5 below.
bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
config="${bundle:+$bundle/config.json}"

if [ ! -f "$template" ]; then
    echo "error: template not found at $template" >&2
    exit 1
fi

# Collision check first — fail before allocating an ID.
# We capture into a variable rather than piping: with `pipefail`, a missing
# archive dir would make `find` exit 1, and the pipeline would report no match
# even when the active dir found one.
search_dirs=("$issues_dir")
[ -d "$archive_dir" ] && search_dirs+=("$archive_dir")
existing_matches="$(find "${search_dirs[@]}" -maxdepth 2 -type d -name "*-${slug}" 2>/dev/null || true)"
if [ -n "$existing_matches" ]; then
    existing="$(echo "$existing_matches" | head -1)"
    echo "error: an issue with slug '${slug}' already exists at $existing" >&2
    exit 3
fi

# Highest existing ID across active + archive.
# `id:` lines look like:  id: 42
# Grep is fine here — frontmatter `id:` is a top-level scalar, no nesting ambiguity.
highest=0
if [ -d "$issues_dir" ]; then
    found=$(find "$issues_dir" -name spec.md -type f -exec grep -h '^id:[[:space:]]*[0-9]\+' {} + 2>/dev/null \
        | awk '{print $2}' \
        | sort -n \
        | tail -1 \
        || true)
    if [ -n "$found" ]; then
        highest="$found"
    fi
fi
# Fold reserved-but-unused IDs from the ledger into the highest-ID scan.
ledger="${issues_dir}/.allocated"
if [ -d "$ledger" ]; then
    marker_max="$(ls -1 "$ledger" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -1 || true)"
    if [ -n "$marker_max" ] && [ "$marker_max" -gt "$highest" ]; then
        highest="$marker_max"
    fi
fi

# Reserve the next ID. Atomic mkdir (no -p) is the compare-and-swap: it fails
# when a parallel session holds the candidate; the loser retries one higher.
mkdir -p "$ledger"
next_id=""
# 10# forces decimal: a hand-padded value ("00089") would otherwise be read
# as octal by $((...)) and abort the script on digits 8/9.
candidate=$((10#$highest))
for _ in $(seq 1 64); do
    candidate=$((candidate + 1))
    if mkdir "${ledger}/${candidate}" 2>/dev/null; then
        next_id="$candidate"
        break
    fi
done
if [ -z "$next_id" ]; then
    echo "error: couldn't reserve an issue ID after 64 attempts; inspect ${ledger}" >&2
    exit 2
fi

# Padding: read issueIdPadding from <bundle>/config.json (default 5).
padding=5
if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
    p=$(jq -r '.issueIdPadding // 5' "$config" 2>/dev/null || echo 5)
    if [[ "$p" =~ ^[0-9]+$ ]]; then
        padding="$p"
    fi
fi

# Grow padding dynamically if next_id is wider than current padding.
id_width=${#next_id}
if [ "$id_width" -gt "$padding" ]; then
    padding="$id_width"
fi

id_padded=$(printf "%0${padding}d" "$next_id")
folder="${issues_dir}/${id_padded}-${slug}"
spec="${folder}/spec.md"
created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Humanize the slug for the title placeholder: "add-user-auth" -> "Add User Auth".
title=$(echo "$slug" | tr '-' ' ' | awk '{
    for (i=1; i<=NF; i++) $i = toupper(substr($i,1,1)) substr($i,2)
    print
}')

mkdir -p "$folder" || { echo "error: couldn't create $folder" >&2; exit 2; }

# Substitute placeholders. Using sed with a unique delimiter to survive slashes in values.
sed \
    -e "s|<<<ID>>>|${next_id}|g" \
    -e "s|<<<ID_PADDED>>>|${id_padded}|g" \
    -e "s|<<<TITLE>>>|${title}|g" \
    -e "s|<<<SLUG>>>|${slug}|g" \
    -e "s|<<<CREATED>>>|${created}|g" \
    "$template" > "$spec" || { echo "error: couldn't write $spec" >&2; exit 2; }

echo "$spec"
