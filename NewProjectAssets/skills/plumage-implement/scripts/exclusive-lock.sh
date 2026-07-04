#!/usr/bin/env bash
# exclusive-lock.sh — hold the shared gate lock for app-instance verification.
#
# Takes the SAME lock precommit-gate.sh uses (lock-lib.sh), so while one
# session drives the app under test (manual launch, computer-use, screenshots),
# parallel gates queue behind it instead of killing the instance via
# --close-instances or stealing input focus mid-verification.
#
# Usage:
#   scripts/exclusive-lock.sh acquire [--wait[=secs]]
#   scripts/exclusive-lock.sh release
#   scripts/exclusive-lock.sh status
#
# Subcommands:
#   acquire   Take the lock. Owner is the *session* PID, not the script's own
#             PID — the script exits immediately, the lock must outlive it.
#             Re-acquiring from the same session is an idempotent success.
#             With --wait, queue behind a live holder (poll every 2 s;
#             default timeout 900 s).
#   release   Remove the lock if this session owns it. Releasing a lock
#             owned by someone else is a no-op with a message.
#   status    Print the owner PID or "free".
#
# Owner resolution: LOCK_OWNER_PID if set; with --session-owner the parent of
# this script's parent (script ← tool shell ← claude session) — the flag agent
# sessions should always pass:
#
#   scripts/exclusive-lock.sh acquire --wait --session-owner
#
# Without either, the parent of this script's process: right interactively
# (the interactive shell lives until the tab closes), ephemeral inside a tool
# shell — hence the flag.
#
# Exit codes:
#   0  success (acquired / released / no-op release / status printed)
#   1  lock held by another live owner (acquire without --wait, or timeout)
#   2  usage or environment error

set -uo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

subcommand="${1:-}"
shift 2>/dev/null || true

wait_for_lock=0
wait_secs=900
session_owner=0
for arg in "$@"; do
    case "$arg" in
        --session-owner) session_owner=1 ;;
        --wait) wait_for_lock=1 ;;
        --wait=*)
            wait_for_lock=1
            wait_secs="${arg#--wait=}"
            case "$wait_secs" in
                ''|0|*[!0-9]*)
                    echo "error: --wait expects a positive integer (got: ${wait_secs:-empty})" >&2
                    exit 2
                    ;;
            esac
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown flag: $arg" >&2; exit 2 ;;
    esac
done

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 2
fi

# See header: agent sessions pass --session-owner (grandparent = the claude
# process); the bare default is this script's parent — right interactively,
# ephemeral inside a tool shell.
if [ "$session_owner" -eq 1 ] && [ -z "${LOCK_OWNER_PID:-}" ]; then
    LOCK_OWNER_PID="$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')"
fi
LOCK_OWNER_PID="${LOCK_OWNER_PID:-$(ps -o ppid= -p $$ | tr -d ' ')}"
export LOCK_OWNER_PID
. "${BASH_SOURCE%/*}/lock-lib.sh"

case "$subcommand" in
    acquire)
        if try_acquire_lock; then
            echo "lock acquired (owner PID $lock_owner_pid, $lock_file)"
            exit 0
        fi
        if [ "$lock_owner" = "$lock_owner_pid" ]; then
            echo "lock already held by this session (PID $lock_owner_pid)"
            exit 0
        fi
        if [ $wait_for_lock -eq 1 ]; then
            echo "waiting for gate lock held by PID $lock_owner (timeout ${wait_secs}s)..." >&2
            wait_start=$(date +%s)
            while [ $(( $(date +%s) - wait_start )) -lt "$wait_secs" ]; do
                sleep 2
                if try_acquire_lock; then
                    echo "lock acquired (owner PID $lock_owner_pid, $lock_file)"
                    exit 0
                fi
                if [ "$lock_owner" = "$lock_owner_pid" ]; then
                    echo "lock already held by this session (PID $lock_owner_pid)"
                    exit 0
                fi
            done
            echo "error: gate lock still held by PID $lock_owner after ${wait_secs}s ($lock_file)." >&2
            echo "       if that PID is not a gate or verification session, remove the lock file (PID recycling)." >&2
            exit 1
        fi
        echo "error: lock held by PID $lock_owner ($lock_file)." >&2
        echo "       pass --wait to queue behind it; a dead owner is taken over automatically." >&2
        exit 1
        ;;
    release)
        owner=$(read_lock_owner "$lock_file")
        if [ -z "$owner" ]; then
            echo "lock already free"
        elif [ "$owner" = "$lock_owner_pid" ]; then
            release_lock
            echo "lock released (was held by this session, PID $lock_owner_pid)"
        else
            echo "lock held by PID $owner, not this session (PID $lock_owner_pid) — leaving it alone"
        fi
        exit 0
        ;;
    status)
        owner=$(read_lock_owner "$lock_file")
        if [ -z "$owner" ]; then
            echo "free"
        else
            alive="dead"
            case "$owner" in
                0|*[!0-9]*) ;;
                *) kill -0 "$owner" 2>/dev/null && alive="alive" ;;
            esac
            echo "held by PID $owner ($alive, $lock_file)"
        fi
        exit 0
        ;;
    ""|-h|--help)
        usage
        exit 0
        ;;
    *)
        echo "error: unknown subcommand: $subcommand (expected acquire|release|status)" >&2
        exit 2
        ;;
esac
