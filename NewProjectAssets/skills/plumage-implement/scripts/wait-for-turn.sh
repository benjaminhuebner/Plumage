#!/usr/bin/env bash
# wait-for-turn.sh — per-checkout FIFO queue for /plumage-implement fresh starts.
#
# A fresh start in a busy checkout enqueues itself and waits; the run starts
# automatically when it is first in line and no run is live. Queue entries are
# `<seq>-<slug>.json` under `<bundle>/runs/queue/`, carrying the waiter's
# session PID. One invocation enqueues (idempotently) and polls in a bounded
# chunk; on timeout the caller re-invokes until granted — same pattern as the
# gate's --wait.
#
# Usage:
#   QUEUE_OWNER_PID=$(ps -o ppid= -p $$) scripts/wait-for-turn.sh <slug> [--timeout=secs]
#   QUEUE_OWNER_PID=$(ps -o ppid= -p $$) scripts/wait-for-turn.sh <slug> --remove
#
# QUEUE_OWNER_PID must be the long-lived session PID (in agent sessions each
# tool shell dies by the next call — the prefix idiom evaluates to the shell's
# parent, the `claude` process). Falls back to the invoking shell's PID for
# interactive use.
#
# --remove deletes this owner's queue entry. The skill calls it right AFTER
# the granted run wrote its run-state (which is what makes it "live"), or on
# abort. Removing before the run-state write would open a window where a
# second waiter sees neither a live run nor an earlier entry.
#
# Turn condition: no live implement run in this checkout's bundle AND the own
# entry is the earliest live entry. A waiter whose PID is dead (missing, zero,
# non-numeric, or kill -0 fails — same rules as the run-state agentPid) never
# blocks; dead entries are removed lazily by the next waiter scanning past.
#
# Exit codes:
#   0  it is this waiter's turn (queue entry kept — remove after run-state write)
#      / --remove done
#   2  usage or environment error
#   3  same-slug conflict: the slug is already running or queued by another
#      live session in this checkout
#   4  timeout — still waiting; re-invoke to keep waiting (position printed)

set -uo pipefail

slug=""
timeout_secs=540
remove=0
for arg in "$@"; do
    case "$arg" in
        --remove) remove=1 ;;
        --timeout=*)
            timeout_secs="${arg#--timeout=}"
            case "$timeout_secs" in
                ''|0|*[!0-9]*)
                    echo "error: --timeout expects a positive integer (got: ${timeout_secs:-empty})" >&2
                    exit 2
                    ;;
            esac
            ;;
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
    echo "usage: wait-for-turn.sh <slug> [--timeout=secs] [--remove]" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi

owner_pid="${QUEUE_OWNER_PID:-$PPID}"
case "$owner_pid" in
    ''|0|*[!0-9]*)
        echo "error: QUEUE_OWNER_PID is not a valid PID (got: ${owner_pid:-empty})" >&2
        exit 2
        ;;
esac

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
queue_dir="$bundle/runs/queue"
mkdir -p "$queue_dir"

# pid_alive <pid> — run-state/queue dead-pid rules: missing, zero, or
# non-numeric is dead (kill -0 0 probes our own process group), else probe.
pid_alive() {
    case "${1:-}" in
        ''|0|*[!0-9]*) return 1 ;;
        *) kill -0 "$1" 2>/dev/null ;;
    esac
}

entry_slug()  { jq -r '.slug // empty' "$1" 2>/dev/null; }
entry_pid()   { jq -r '.agentPid // empty' "$1" 2>/dev/null; }

own_entry=""
find_own_entry() {
    own_entry=""
    local f
    for f in "$queue_dir"/*.json; do
        [ -f "$f" ] || continue
        if [ "$(entry_slug "$f")" = "$slug" ] && [ "$(entry_pid "$f")" = "$owner_pid" ]; then
            own_entry="$f"
            return 0
        fi
    done
    return 1
}

if [ $remove -eq 1 ]; then
    if find_own_entry; then
        rm -f "$own_entry"
        echo "queue entry removed: ${own_entry##*/}"
    else
        echo "no queue entry for $slug owned by PID $owner_pid (already removed?)"
    fi
    exit 0
fi

# ---- Same-slug refusal in this checkout --------------------------------------

run_state="$bundle/runs/$slug.json"
if [ -f "$run_state" ] && pid_alive "$(jq -r '.agentPid // empty' "$run_state" 2>/dev/null)"; then
    echo "error: $slug is already being implemented in this checkout (live run, PID $(jq -r '.agentPid' "$run_state"))" >&2
    exit 3
fi
for f in "$queue_dir"/*.json; do
    [ -f "$f" ] || continue
    [ "$(entry_slug "$f")" = "$slug" ] || continue
    pid="$(entry_pid "$f")"
    if [ "$pid" != "$owner_pid" ] && pid_alive "$pid"; then
        echo "error: $slug is already queued in this checkout by PID $pid (${f##*/})" >&2
        exit 3
    fi
done

# ---- Enqueue (idempotent; hard-link allocation like lock-lib.sh) -------------

if ! find_own_entry; then
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    tmp="$queue_dir/.enqueue.$$"
    printf '{\n  "slug": "%s",\n  "agentPid": %s,\n  "enqueuedAt": "%s"\n}\n' \
        "$slug" "$owner_pid" "$now" > "$tmp"
    # Claim the sequence number with an atomic mkdir before linking the entry:
    # two concurrent enqueues of different slugs would otherwise both link the
    # same number under different filenames. Claim dirs count toward max.
    while :; do
        max=0
        for f in "$queue_dir"/*.json "$queue_dir"/.seq-*; do
            [ -e "$f" ] || continue
            seq="${f##*/}"; seq="${seq#.seq-}"; seq="${seq%%-*}"; seq="${seq%.json}"
            case "$seq" in *[!0-9]*|'') continue ;; esac
            seq=$((10#$seq))
            [ "$seq" -gt "$max" ] && max=$seq
        done
        next=$(printf '%06d' $((max + 1)))
        if mkdir "$queue_dir/.seq-$next" 2>/dev/null; then
            own_entry="$queue_dir/$next-$slug.json"
            ln "$tmp" "$own_entry"
            rmdir "$queue_dir/.seq-$next"
            break
        fi
    done
    rm -f "$tmp"
    echo "enqueued as ${own_entry##*/}"
fi
own_name="${own_entry##*/}"

# ---- Poll until turn or timeout ----------------------------------------------

deadline=$(( $(date +%s) + timeout_secs ))
last_report=""
while :; do
    # A live implement run in this checkout blocks everyone.
    blocker=""
    for f in "$bundle"/runs/*.json; do
        [ -f "$f" ] || continue
        [ "$(jq -r '.kind // empty' "$f" 2>/dev/null)" = "implement" ] || continue
        if pid_alive "$(jq -r '.agentPid // empty' "$f" 2>/dev/null)"; then
            blocker="$(jq -r '.issue // empty' "$f")"
            break
        fi
    done

    # Earlier live entries block; earlier dead entries are removed lazily.
    # "Earlier" is filename order (zero-padded seq, slug as tie-break), which
    # every waiter computes identically.
    position=1
    if [ -z "$blocker" ]; then earliest_live_is_me=1; else earliest_live_is_me=0; fi
    for f in "$queue_dir"/*.json; do
        [ -f "$f" ] || continue
        fname="${f##*/}"
        [ "$fname" = "$own_name" ] && continue
        [ "$fname" \< "$own_name" ] || continue
        if pid_alive "$(entry_pid "$f")"; then
            earliest_live_is_me=0
            position=$((position + 1))
            [ -z "$blocker" ] && blocker="$(entry_slug "$f")"
        else
            rm -f "$f"
        fi
    done

    if [ $earliest_live_is_me -eq 1 ]; then
        echo "it is $slug's turn — proceed with fresh start, then remove the entry (--remove)"
        exit 0
    fi

    report="waiting behind $blocker (position $position)"
    if [ "$report" != "$last_report" ]; then
        echo "$report — run in parallel instead: scripts/setup-worktree.sh $slug" >&2
        last_report="$report"
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "still waiting after ${timeout_secs}s: $report — re-invoke to keep waiting" >&2
        exit 4
    fi
    sleep 2
done
