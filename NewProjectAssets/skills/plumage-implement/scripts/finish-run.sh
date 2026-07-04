#!/bin/bash
# Archives a finished run: sets the spec to waiting-for-review (outcome
# `completed` only), enriches <bundle>/runs/<slug>.json with finishedAt +
# outcome and moves it to <bundle>/runs/history/<slug>/<stamp>.json. The
# status flips BEFORE the archive move because the move is the completion
# signal Plumage's notifier keys on — the UI must already see the new status.
set -euo pipefail

slug="${1:?usage: finish-run.sh <slug> [outcome]}"
outcome="${2:-completed}"
script_dir="$(cd "$(dirname "$0")" && pwd)"

bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
if [ -z "$bundle" ]; then
    echo "error: no .plumage bundle in $(pwd)" >&2
    exit 2
fi

if [ "$outcome" = "completed" ]; then
    issues_dir=$(jq -r '.paths.issues // ".claude/issues"' "$bundle/config.json" 2>/dev/null || echo ".claude/issues")
    spec="$issues_dir/$slug/spec.md"
    if [ -f "$spec" ]; then
        python3 "$script_dir/spec-set-status.py" "$spec" waiting-for-review >/dev/null \
            || echo "warning: could not set spec status to waiting-for-review — set it manually" >&2
    else
        echo "warning: spec not found at $spec — status not flipped" >&2
    fi
fi

run_state="$bundle/runs/$slug.json"
if [ ! -f "$run_state" ]; then
    echo "error: run-state not found at $run_state" >&2
    exit 2
fi

finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Colon-free stamp: Finder rewrites ':' in file names. The app reads the
# finishedAt JSON field, the name only sorts and dedupes.
stamp=$(date -u +%Y%m%dT%H%M%SZ)
history_dir="$bundle/runs/history/$slug"
mkdir -p "$history_dir"

target="$history_dir/$stamp.json"
if [ -e "$target" ]; then
    target="$history_dir/$stamp-$$.json"
fi

tmp="$target.tmp"
if ! jq --arg finishedAt "$finished_at" --arg outcome "$outcome" \
    '. + {finishedAt: $finishedAt, outcome: $outcome}' "$run_state" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "error: could not enrich run-state (invalid JSON?): $run_state" >&2
    exit 2
fi
mv "$tmp" "$target"
rm -f "$run_state"
echo "run-state archived: $target (outcome: $outcome)"
