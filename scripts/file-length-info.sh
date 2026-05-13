#!/usr/bin/env bash
# file-length-info.sh — informational, non-blocking check for long .swift files.
#
# Discipline anchor for the architecture decision to NOT use SwiftLint's
# file_length / type_body_length / function_body_length rules (decisions.md
# 2026-05-13 #00009-architecture-restructure). SwiftUI's ViewBuilder distorts
# those metrics, so 5/7 large mature Swift apps disable them. This script
# replaces them with a soft warning when a staged Swift file crosses 400 lines.
#
# Output:
#   [info] file-length: <one line per file >400 lines, or nothing>
#
# Exit code: always 0. Never blocks a commit.
#
# Invoke either manually before committing, or from precommit-gate.sh as the
# trailing info step. Written for Bash 3.2 (macOS default) — no mapfile.

set -uo pipefail

threshold=400

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
    echo "[info] file-length: not inside a git repository — skipped" >&2
    exit 0
fi
cd "$repo_root"

over_threshold=""
count=0
while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue
    lines=$(wc -l <"$file" | tr -d ' ')
    if [ "$lines" -gt "$threshold" ]; then
        over_threshold="${over_threshold}    ${file} (${lines} lines)
"
        count=$((count + 1))
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.swift' 2>/dev/null)

if [ "$count" -eq 0 ]; then
    exit 0
fi

printf '[info] file-length: %d staged .swift file(s) over %d lines (not blocking):\n' "$count" "$threshold"
printf '%s' "$over_threshold"
exit 0
