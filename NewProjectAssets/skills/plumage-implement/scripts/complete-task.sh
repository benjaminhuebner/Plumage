#!/usr/bin/env bash
# complete-task.sh — single-call task completion for /plumage-implement.
#
# Chains the per-task bookkeeping that used to take 5-7 separate agent calls:
# branch assert → pre-commit gate → spec task tick → run-state update.
# `git add` and `git commit` stay OUTSIDE this script so the git-policy hooks
# keep matching on literal command text.
#
# Usage:
#   scripts/complete-task.sh <slug> [--first-commit] [--skip-build] [--full]
#
# <slug> is the issue folder name under the issues dir (e.g.
# 00042-add-user-auth). Flags are forwarded to precommit-gate.sh, which always
# runs with --wait=1800 --close-instances.
#
# Which task this call completes is derived, not passed: lastCompletedTask
# from the run-state plus the commit count since headBeforeRun. A re-run after
# a hook-blocked commit (task commit missing) completes the SAME task again —
# the gate re-runs on the fixed tree, the already-ticked spec is left alone,
# and the run-state write repeats the same values. Idempotent by construction.
#
# Exit codes:
#   0  task completed (gate passed, spec ticked, run-state updated)
#   2  usage or environment error (bad flag, missing bundle/spec/run-state)
#   3  branch mismatch (run-state phase set to "failed at task <n>")
#   *  other non-zero: propagated from precommit-gate.sh (1 = check failure,
#      2 = gate environment problem); nothing has been modified

set -uo pipefail

# ---- Argument parsing -------------------------------------------------------

slug=""
gate_flags=()
for arg in "$@"; do
    case "$arg" in
        --first-commit|--skip-build|--full) gate_flags+=("$arg") ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "error: unknown flag: $arg" >&2
            exit 2
            ;;
        *)
            if [ -n "$slug" ]; then
                echo "error: more than one slug given ($slug, $arg)" >&2
                exit 2
            fi
            slug="$arg"
            ;;
    esac
done
if [ -z "$slug" ]; then
    echo "usage: complete-task.sh <slug> [--first-commit] [--skip-build] [--full]" >&2
    exit 2
fi

# ---- Environment ------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
    echo "error: not inside a git repository" >&2
    exit 2
fi
script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$repo_root"

bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
if [ -z "$bundle" ]; then
    echo "error: no *.plumage bundle found in $repo_root" >&2
    exit 2
fi

issues_dir=$(jq -r '.paths.issues // ".claude/issues"' "$bundle/config.json" 2>/dev/null || echo ".claude/issues")
spec="$issues_dir/$slug/spec.md"
if [ ! -f "$spec" ]; then
    echo "error: spec not found at $spec" >&2
    exit 2
fi

run_state="$bundle/runs/$slug.json"
if [ ! -f "$run_state" ]; then
    echo "error: run-state not found at $run_state (is this run started?)" >&2
    exit 2
fi
if ! jq -e . "$run_state" >/dev/null 2>&1; then
    echo "error: run-state is not valid JSON: $run_state" >&2
    exit 2
fi

# ---- Derive which task this call completes ----------------------------------

last_completed=$(jq -r '.lastCompletedTask // 0' "$run_state")
case "$last_completed" in ''|*[!0-9]*) last_completed=0 ;; esac

head_before=$(jq -r '.headBeforeRun // empty' "$run_state")
commits=$last_completed
if [ -n "$head_before" ] && git rev-parse -q --verify "$head_before^{commit}" >/dev/null 2>&1; then
    commits=$(git rev-list --count "$head_before"..HEAD 2>/dev/null || echo "$last_completed")
fi
case "$commits" in ''|*[!0-9]*) commits=$last_completed ;; esac

if [ "$commits" -ge "$last_completed" ]; then
    n=$((last_completed + 1))
else
    n=$last_completed
fi

# Fence-aware count of ticked/unchecked tasks under ## Tasks (counting only;
# the precise per-line edit stays in spec-task-tick.py).
counts=$(awk '
    /^## Tasks[ \t]*$/ { in_tasks = 1; next }
    /^## /             { in_tasks = 0 }
    !in_tasks          { next }
    /^(```|~~~)/       { fence = !fence; next }
    fence              { next }
    /^- \[ \]/         { unchecked++ }
    /^- \[[xX]\]/      { ticked++ }
    END { printf "%d %d", ticked + 0, unchecked + 0 }
' "$spec")
ticked=${counts% *}
unchecked=${counts#* }
total=$((ticked + unchecked))

if [ "$n" -gt "$total" ]; then
    echo "error: nothing left to complete — all $total tasks are done and committed" >&2
    exit 2
fi

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Read-modify-write so Plumage-owned fields survive; atomic tmp + mv.
write_run_state() {
    local tmp="$run_state.tmp"
    if jq --arg now "$(now)" "$1" "$run_state" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$run_state"
    else
        rm -f "$tmp"
        echo "error: run-state update failed ($run_state)" >&2
        return 1
    fi
}

# ---- Branch assert ----------------------------------------------------------

expected_branch=$(jq -r '.branch // empty' "$run_state")
if [ -z "$expected_branch" ]; then
    branch_prefix=$(jq -r '.git.branchPrefix // "issue/"' "$bundle/config.json" 2>/dev/null || echo "issue/")
    expected_branch="${branch_prefix}${slug}"
fi
current_branch=$(git branch --show-current 2>/dev/null || true)
if [ "$current_branch" != "$expected_branch" ]; then
    write_run_state ".phase = \"failed at task $n\" | .lastProgressAt = \$now" || true
    echo "error: on branch '${current_branch:-<detached>}', expected '$expected_branch' —" >&2
    echo "       the checkout was switched underneath the run; not committing onto a foreign branch" >&2
    exit 3
fi

# ---- Pre-commit gate ----------------------------------------------------------

echo "completing task $n/$total of $slug (ticked: $ticked, commits since start: $commits)"
"$script_dir/precommit-gate.sh" --wait=1800 --close-instances ${gate_flags[@]+"${gate_flags[@]}"}
gate_rc=$?
if [ "$gate_rc" -ne 0 ]; then
    exit "$gate_rc"
fi

# ---- Tick + run-state ---------------------------------------------------------

if [ "$ticked" -ge "$n" ]; then
    echo "tick: task $n already ticked — idempotent re-run, spec left alone"
else
    if ! python3 "$script_dir/spec-task-tick.py" "$spec" --task 1; then
        echo "error: spec-task-tick failed for $spec" >&2
        exit 2
    fi
fi

if [ $((total - n)) -le 0 ]; then
    next_phase="pre-commit-gate"
else
    next_phase="running task $((n + 1))"
fi
write_run_state ".lastCompletedTask = $n | .phase = \"$next_phase\" | .lastProgressAt = \$now" || exit 2

echo "task $n/$total complete: $slug — next phase: $next_phase"
