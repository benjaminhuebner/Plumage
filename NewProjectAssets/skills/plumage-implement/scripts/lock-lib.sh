# lock-lib.sh — shared single-instance lock for xcodebuild-serializing tools.
#
# Sourced (not executed) by precommit-gate.sh and exclusive-lock.sh. Two
# xcodebuild invocations against the same project deadlock over
# DerivedData/SWBBuildService, so every tool that may run xcodebuild — or
# must keep others from running it — takes this one lock. It is keyed on the
# absolute git common dir (identical across worktrees; macOS has no flock).
# The lock is a file holding the owner PID; a lock whose owner is dead is
# taken over automatically, so a kill -9'd holder never blocks the next run.
#
# Requires: cwd inside the git repository.
# Defines:  lock_file, lock_owner, read_lock_owner, try_acquire_lock,
#           release_lock.
# Owner PID: defaults to the sourcing process ($$). Set LOCK_OWNER_PID before
# sourcing to register a longer-lived owner (e.g. the claude session PID) —
# the short-lived script process dies, the lock must outlive it.

lock_owner_pid="${LOCK_OWNER_PID:-$$}"

git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
lock_key=$(printf '%s' "${git_common_dir:-$PWD}" | shasum 2>/dev/null | cut -c1-12 || echo default)
lock_file="${TMPDIR:-/tmp}/plumage-precommit-gate-${lock_key}.lock"

# Reads the owner PID of a lock at $1 — a PID file, or a pre-hard-link-era
# lock directory with the PID at <dir>/pid.
read_lock_owner() {
    cat "$1" 2>/dev/null || cat "$1/pid" 2>/dev/null || true
}

# Acquire by hard-linking a private temp file (content: the owner PID) to the
# lock path — link(2) is atomic, so the lock can never exist without its
# owner PID. On contention with a live owner, returns 1 with lock_owner set.
lock_owner=""
try_acquire_lock() {
    local tmp="$lock_file.$$"
    printf '%s' "$lock_owner_pid" > "$tmp"
    while :; do
        if ln "$tmp" "$lock_file" 2>/dev/null; then
            if [ "$(cat "$lock_file" 2>/dev/null || true)" = "$lock_owner_pid" ]; then
                rm -f "$tmp"
                return 0
            fi
            # ln linked INTO a pre-hard-link-era lock dir (and "succeeded").
            # Undo, then fall through to the stale/owner handling below.
            rm -f "$lock_file/${tmp##*/}" 2>/dev/null
        fi
        local owner stale=0
        owner=$(read_lock_owner "$lock_file")
        if [ -z "$owner" ]; then
            # Gone between ln and cat → retry. Present but contentless can
            # only be a corrupt lock or an ownerless old-format dir → stale.
            [ -e "$lock_file" ] || continue
            stale=1
        else
            # Validate before kill -0: a zero/garbage PID would probe our own
            # process group and read as a live owner forever.
            case "$owner" in
                0|*[!0-9]*) stale=1 ;;
                *) kill -0 "$owner" 2>/dev/null || stale=1 ;;
            esac
        fi
        if [ $stale -eq 1 ]; then
            # mv is atomic: one takeover wins. Re-check content before delete;
            # if it changed we grabbed someone's fresh lock — put it back.
            local grave="$lock_file.stale.$$"
            if mv "$lock_file" "$grave" 2>/dev/null; then
                if [ "$(read_lock_owner "$grave")" = "$owner" ]; then
                    rm -rf "$grave"
                else
                    mv "$grave" "$lock_file" 2>/dev/null || rm -rf "$grave"
                fi
            fi
            continue
        fi
        rm -f "$tmp"
        lock_owner="$owner"
        return 1
    done
}

# Ownership-checked release: never delete a lock another process has since
# (rightly or wrongly) taken over.
release_lock() {
    if [ "$(cat "$lock_file" 2>/dev/null || true)" = "$lock_owner_pid" ]; then
        rm -f "$lock_file"
    fi
    rm -f "$lock_file.$$"
}
