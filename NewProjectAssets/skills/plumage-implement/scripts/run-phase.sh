#!/usr/bin/env bash
# run-phase.sh — atomically set the run-state `phase` (+ lastProgressAt).
#
# For the phase writes the agent makes outside the per-task loop:
# "failed at task <n>" when a task is given up, and "needs-input: <question>"
# when the run blocks on the user (the Stop hook allows the turn to end only
# on a finished, failed, or needs-input run). complete-task.sh keeps owning
# the in-loop phase transitions.
#
# Usage:
#   scripts/run-phase.sh <slug> <phase>
#
# Exit codes:
#   0  phase written
#   2  usage or environment error (no bundle, no run-state, invalid JSON)

set -uo pipefail

if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    echo "usage: run-phase.sh <slug> <phase>" >&2
    exit 2
fi
slug="$1"
phase="$2"

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
    echo "error: not inside a git repository" >&2
    exit 2
fi
cd "$repo_root"

bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
if [ -z "$bundle" ]; then
    echo "error: no *.plumage bundle found in $repo_root" >&2
    exit 2
fi

run_state="$bundle/runs/$slug.json"
if [ ! -f "$run_state" ]; then
    echo "error: run-state not found at $run_state" >&2
    exit 2
fi
if ! jq -e . "$run_state" >/dev/null 2>&1; then
    echo "error: run-state is not valid JSON: $run_state" >&2
    exit 2
fi

tmp="$run_state.tmp"
if jq --arg phase "$phase" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = $phase | .lastProgressAt = $now' "$run_state" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$run_state"
    echo "phase: $phase ($slug)"
else
    rm -f "$tmp"
    echo "error: run-state update failed ($run_state)" >&2
    exit 2
fi
