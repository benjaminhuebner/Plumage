#!/usr/bin/env bash
# keep-implement-run-alive.sh — Stop hook
#
# Blocks the turn from ending while THIS session owns an unfinished
# /plumage-implement run. Legitimate turn ends stay possible: a finished run
# was archived by finish-run.sh (no run-state left), a failed run carries
# phase "failed at task <n>", and a run blocked on the user carries phase
# "needs-input: <question>" (written via run-phase.sh). Everything else is an
# early stop — the hook sends the agent back to work with the next task named.
#
# Session association is by PID ancestry: the run-state's agentPid is the
# claude process, which is an ancestor of this hook process. Sessions without
# a run (normal chats, plan, review) are never touched. Claude Code overrides
# the hook after 8 consecutive blocks, so a wedged state cannot loop forever.
#
# Fail OPEN: missing jq, no bundle, malformed JSON → exit 0. The failure mode
# is "an early stop slips through" — the pre-Stop-hook status quo.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ -z "$input" ] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | jq -r '.cwd // empty')}"
[ -n "$project_dir" ] && [ -d "$project_dir" ] || exit 0

bundle=$(find "$project_dir" -maxdepth 1 -type d -name '*.plumage' ! -name '.*' 2>/dev/null | head -1)
[ -n "$bundle" ] || exit 0

ancestors=" "
walker=$$
while [ -n "$walker" ] && [ "$walker" -gt 1 ] 2>/dev/null; do
    ancestors="$ancestors$walker "
    walker=$(ps -o ppid= -p "$walker" 2>/dev/null | tr -d ' ')
done

scripts_rel=".claude/skills/plumage-implement/scripts"

# ---- Live run owned by this session? -------------------------------------------

for rs in "$bundle"/runs/*.json; do
    [ -f "$rs" ] || continue
    [ "$(jq -r '.kind // empty' "$rs" 2>/dev/null)" = "implement" ] || continue
    pid=$(jq -r '.agentPid // empty' "$rs" 2>/dev/null)
    case "$pid" in ''|0|*[!0-9]*) continue ;; esac
    case "$ancestors" in *" $pid "*) ;; *) continue ;; esac

    slug=$(jq -r '.issue // empty' "$rs" 2>/dev/null)
    phase=$(jq -r '.phase // empty' "$rs" 2>/dev/null)
    case "$phase" in
        failed*|needs-input*) exit 0 ;;
    esac

    issues_dir=$(jq -r '.paths.issues // ".claude/issues"' "$bundle/config.json" 2>/dev/null || echo ".claude/issues")
    spec="$project_dir/$issues_dir/$slug/spec.md"
    next_task=""
    if [ -f "$spec" ]; then
        next_task=$(awk '
            /^## Tasks[ \t]*$/ { in_tasks = 1; next }
            /^## /             { in_tasks = 0 }
            !in_tasks          { next }
            /^(```|~~~)/       { fence = !fence; next }
            fence              { next }
            /^- \[ \]/         { print substr($0, 7, 140); exit }
        ' "$spec")
    fi

    if [ -n "$next_task" ]; then
        work_line="Next unchecked task: $next_task"
    else
        work_line="All tasks are ticked: run the final gate (complete-task.sh $slug --final-gate), write PR.md, record learnings, then archive with $scripts_rel/finish-run.sh $slug."
    fi

    cat >&2 <<EOF
The /plumage-implement run for '$slug' is not finished (phase: ${phase:-unknown}). Do not end the turn.

$work_line

Legitimate ways to end the turn instead:
- Run finished: $scripts_rel/finish-run.sh $slug (flips the spec to waiting-for-review and archives the run-state).
- Task failed twice and the cause is unclear: $scripts_rel/run-phase.sh $slug "failed at task <n>", then report what failed.
- Blocked on a decision only the user can make: $scripts_rel/run-phase.sh $slug "needs-input: <one-line question>", then ask and stop.
EOF
    exit 2
done

# ---- Queued fresh start owned by this session? ----------------------------------

for qf in "$bundle"/runs/queue/*.json; do
    [ -f "$qf" ] || continue
    pid=$(jq -r '.agentPid // empty' "$qf" 2>/dev/null)
    case "$pid" in ''|0|*[!0-9]*) continue ;; esac
    case "$ancestors" in *" $pid "*) ;; *) continue ;; esac
    slug=$(jq -r '.slug // empty' "$qf" 2>/dev/null)

    cat >&2 <<EOF
This session is still queued to implement '$slug'. Do not end the turn.

Keep re-invoking $scripts_rel/start-run.sh $slug — exit 4 means still waiting, re-invoke again. If the user aborted the run, remove the entry first: $scripts_rel/wait-for-turn.sh $slug --remove.
EOF
    exit 2
done

exit 0
