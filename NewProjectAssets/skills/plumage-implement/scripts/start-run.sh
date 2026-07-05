#!/usr/bin/env bash
# start-run.sh — single-call run start for /plumage-implement.
#
# Chains the fresh-start/resume bookkeeping that used to take 6-8 separate
# agent calls: status dispatch → dirty-tree check → same-slug guard across all
# worktrees → FIFO queue wait → branch checkout → run-state write → queue-entry
# removal → spec status flip. Idempotent: re-invoking after exit 4 (still
# queued) or after a crash converges on the same started run.
#
# The session PID (run-state agentPid, queue owner) is resolved INSIDE the
# script: parent of this script's parent — in an agent session that is the
# long-lived `claude` process (script ← tool shell ← claude). QUEUE_OWNER_PID
# overrides for callers that know better.
#
# Usage:
#   scripts/start-run.sh <slug> [--timeout=secs]
#
# <slug> is the issue folder name under the issues dir; the id prefix may be
# omitted if the suffix is unique (same resolution as setup-worktree.sh).
#
# Exit codes:
#   0  run started (branch checked out, run-state live, spec in-progress)
#   2  usage or environment error
#   3  same-slug conflict: already running or queued (any worktree)
#   4  still waiting in this checkout's queue — re-invoke to keep waiting
#   5  dirty working tree on fresh start — user must stash/commit/discard
#   6  wrong spec status for implement (draft of a type whose "draft blocks
#      implement" flag is on / waiting-for-review / done) — the message names
#      the right next step

set -uo pipefail

slug_arg=""
timeout_arg=""
for arg in "$@"; do
    case "$arg" in
        --timeout=*) timeout_arg="$arg" ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "error: unknown flag: $arg" >&2
            exit 2
            ;;
        *)
            if [ -n "$slug_arg" ]; then
                echo "error: more than one slug given ($slug_arg, $arg)" >&2
                exit 2
            fi
            slug_arg="$arg"
            ;;
    esac
done
if [ -z "$slug_arg" ]; then
    echo "usage: start-run.sh <slug> [--timeout=secs]" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required" >&2
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

# ---- Slug resolution (exact folder name, or unique suffix) --------------------

slug=""
if [ -d "$issues_dir/$slug_arg" ]; then
    slug="$slug_arg"
else
    matches=()
    for d in "$issues_dir"/*-"$slug_arg"; do
        [ -d "$d" ] && matches+=("$d")
    done
    if [ ${#matches[@]} -eq 1 ]; then
        slug=$(basename "${matches[0]}")
    elif [ ${#matches[@]} -gt 1 ]; then
        echo "error: ambiguous slug '$slug_arg' — matches:" >&2
        printf '       %s\n' "${matches[@]##*/}" >&2
        exit 2
    fi
fi
if [ -z "$slug" ]; then
    echo "error: no issue folder matches '$slug_arg' under $issues_dir" >&2
    exit 2
fi
spec="$issues_dir/$slug/spec.md"
if [ ! -f "$spec" ]; then
    echo "error: spec not found at $spec" >&2
    exit 2
fi

# ---- Status/type dispatch -----------------------------------------------------

fm_field() {
    awk -v key="$1" '/^---[ \t]*$/{c++; next} c==1 && $1 == key":" {print $2; exit} c>=2{exit}' "$spec"
}
status=$(fm_field status)
type=$(fm_field type)

# Whether a draft of this type blocks implement comes from Plumage's app-wide
# issue-type catalog (Settings → Issue Types). Fallback when the catalog file
# is missing or doesn't list the type: built-in defaults — only 'feature'
# blocks; unknown types block (implementing an unvetted draft is the risky
# direction).
draft_blocks_implement() {
    local t="$1"
    local types_file="$HOME/Library/Application Support/Plumage/issue-types.json"
    local flag=""
    if [ -f "$types_file" ]; then
        # Readable non-empty catalog: a type it doesn't list blocks ("true"),
        # matching the app. Missing/corrupt/empty catalog: flag stays "" and
        # the built-in defaults below apply, also matching the app.
        flag=$(jq -r --arg t "$t" '
            if ((.types // []) | length) == 0 then ""
            else (([.types[] | select(.name == $t) | .draftBlocksImplement | tostring] | first) // "true")
            end' "$types_file" 2>/dev/null) || flag=""
    fi
    if [ -z "$flag" ]; then
        case "$t" in
            chore|spike|refactor) flag="false" ;;
            *) flag="true" ;;
        esac
    fi
    [ "$flag" != "false" ]
}

mode=""
case "$status" in
    approved) mode="fresh" ;;
    in-progress) mode="resume" ;;
    draft)
        if draft_blocks_implement "$type"; then
            echo "error: spec is draft and type '$type' needs planning — run /plumage-plan $slug first (per-type draft blocking: Plumage Settings → Issue Types)" >&2
            exit 6
        fi
        mode="fresh"
        ;;
    waiting-for-review|done)
        echo "error: spec status is '$status' — this issue is past implementation" >&2
        exit 6
        ;;
    *)
        echo "error: unrecognized spec status '$status' in $spec" >&2
        exit 6
        ;;
esac

# ---- Dirty-tree check (fresh only) ---------------------------------------------

if [ "$mode" = "fresh" ]; then
    dirty=$(git status --porcelain 2>/dev/null || true)
    if [ -n "$dirty" ]; then
        echo "error: working tree is dirty — stash, commit, or discard before a fresh start:" >&2
        printf '%s\n' "$dirty" | sed 's/^/       /' >&2
        exit 5
    fi
fi

# ---- Session PID ---------------------------------------------------------------
# Parent of this script's parent: script ← tool shell ← claude session. The
# tool shell dies by the next call; its parent is the long-lived owner. In an
# interactive terminal that resolves to the terminal app — also long-lived.

owner_pid="${QUEUE_OWNER_PID:-$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')}"
case "$owner_pid" in
    ''|0|*[!0-9]*)
        echo "error: could not resolve a session PID (got: ${owner_pid:-empty})" >&2
        exit 2
        ;;
esac

pid_alive() {
    case "${1:-}" in
        ''|0|*[!0-9]*) return 1 ;;
        *) kill -0 "$1" 2>/dev/null ;;
    esac
}

# ---- Same-slug guard across ALL worktrees --------------------------------------
# A live run or queue entry for this slug anywhere means the issue is already
# being worked on. Entries owned by this session are ours (idempotent re-entry).

while IFS= read -r wt; do
    [ -n "$wt" ] && [ -d "$wt" ] || continue
    wt_bundle=$(find "$wt" -maxdepth 1 -type d -name '*.plumage' ! -name '.*' 2>/dev/null | head -1)
    [ -n "$wt_bundle" ] || continue
    rs="$wt_bundle/runs/$slug.json"
    if [ -f "$rs" ]; then
        rs_pid=$(jq -r '.agentPid // empty' "$rs" 2>/dev/null)
        if [ "$rs_pid" != "$owner_pid" ] && pid_alive "$rs_pid"; then
            echo "error: $slug already has a live run in $wt (PID $rs_pid)" >&2
            exit 3
        fi
    fi
    for qf in "$wt_bundle"/runs/queue/*.json; do
        [ -f "$qf" ] || continue
        [ "$(jq -r '.slug // empty' "$qf" 2>/dev/null)" = "$slug" ] || continue
        q_pid=$(jq -r '.agentPid // empty' "$qf" 2>/dev/null)
        if [ "$q_pid" != "$owner_pid" ] && pid_alive "$q_pid"; then
            echo "error: $slug is already queued in $wt by PID $q_pid" >&2
            exit 3
        fi
    done
done < <(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10)}')

# ---- FIFO queue for this checkout ----------------------------------------------

QUEUE_OWNER_PID="$owner_pid" "$script_dir/wait-for-turn.sh" "$slug" ${timeout_arg:+"$timeout_arg"}
turn_rc=$?
if [ "$turn_rc" -ne 0 ]; then
    # 4 = still waiting (re-invoke), 3 = same-slug conflict, 2 = env error.
    exit "$turn_rc"
fi

remove_queue_entry() {
    QUEUE_OWNER_PID="$owner_pid" "$script_dir/wait-for-turn.sh" "$slug" --remove >/dev/null 2>&1 || true
}

bail() {
    remove_queue_entry
    echo "error: $1" >&2
    exit 2
}

# ---- Branch ---------------------------------------------------------------------

branch_prefix=$(jq -r '.git.branchPrefix // "issue/"' "$bundle/config.json" 2>/dev/null || echo "issue/")
branch="${branch_prefix}${slug}"

default_branch=$(jq -r '.git.defaultBranch // empty' "$bundle/config.json" 2>/dev/null || true)
if [ -z "$default_branch" ]; then
    if git show-ref --verify --quiet refs/heads/main; then default_branch=main
    elif git show-ref --verify --quiet refs/heads/master; then default_branch=master; fi
fi
[ -n "$default_branch" ] || bail "cannot determine the default branch (no config entry, no main/master)"

current_branch=$(git branch --show-current 2>/dev/null || true)
if [ "$current_branch" != "$branch" ]; then
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git checkout "$branch" >/dev/null 2>&1 \
            || bail "cannot check out $branch (checked out in another worktree? that run owns the issue)"
    elif [ "$mode" = "resume" ]; then
        bail "spec says in-progress but branch $branch does not exist — inconsistent state, inspect manually"
    else
        git checkout -b "$branch" "$default_branch" >/dev/null 2>&1 \
            || bail "could not create $branch from $default_branch"
    fi
fi

# ---- Run-state write -------------------------------------------------------------

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
if [ "$total" -eq 0 ]; then
    bail "spec has no tasks under '## Tasks' — add the task list before starting the run"
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
head_before=$(git rev-parse "$default_branch" 2>/dev/null) || bail "git rev-parse $default_branch failed"
run_state="$bundle/runs/$slug.json"
mkdir -p "$bundle/runs"

new_ulid() {
    python3 -c '
import os, time
alph = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
v = (int(time.time() * 1000) << 80) | int.from_bytes(os.urandom(10), "big")
print("".join(alph[(v >> (5 * i)) & 31] for i in range(25, -1, -1)))
'
}

src='{}'
if [ -f "$run_state" ] && jq -e . "$run_state" >/dev/null 2>&1; then
    src=$(cat "$run_state")
fi
run_id=$(printf '%s' "$src" | jq -r '.runId // empty')
[ -n "$run_id" ] || run_id=$(new_ulid)
started_at=$(printf '%s' "$src" | jq -r '.startedAt // empty')
[ -n "$started_at" ] || started_at="$now"
existing_head=$(printf '%s' "$src" | jq -r '.headBeforeRun // empty')
[ -n "$existing_head" ] && head_before="$existing_head"

tmp="$run_state.tmp"
if printf '%s' "$src" | jq \
    --arg runId "$run_id" --arg issue "$slug" --arg startedAt "$started_at" \
    --arg now "$now" --arg branch "$branch" --arg head "$head_before" \
    --argjson agentPid "$owner_pid" --argjson last "$ticked" --argjson total "$total" \
    '.kind = "implement" | .runId = $runId | .issue = $issue
     | .startedAt = $startedAt | .agentPid = $agentPid
     | .phase = "starting" | .lastProgressAt = $now
     | .branch = $branch | .headBeforeRun = $head
     | .lastCompletedTask = $last | .totalTasks = $total' > "$tmp" 2>/dev/null; then
    mv "$tmp" "$run_state"
else
    rm -f "$tmp"
    bail "run-state write failed ($run_state)"
fi

# Run-state is live — it now blocks the next waiter; the queue entry can go.
remove_queue_entry

# ---- Spec status flip -------------------------------------------------------------

if [ "$status" != "in-progress" ]; then
    python3 "$script_dir/spec-set-status.py" "$spec" in-progress >/dev/null \
        || echo "warning: could not set spec status to in-progress — set it manually" >&2
fi

next_task=$((ticked + 1))
echo "run started ($mode): $slug — branch $branch, next task $next_task/$total (agentPid $owner_pid)"
