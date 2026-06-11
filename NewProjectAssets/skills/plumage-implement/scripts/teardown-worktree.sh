#!/usr/bin/env bash
# teardown-worktree.sh — remove a parallel /plumage-implement worktree after merge.
#
# Removes ../<project>-<slug> (refuses while its tree is dirty) and deletes
# issue/<slug> only when the issue spec says `status: done` — issues are
# squash-merged, so git ancestry can never prove "merged"; the spec status is
# the project's source of truth. Otherwise the branch is kept and the reason
# printed.
#
# Usage:
#   scripts/teardown-worktree.sh <slug> [--force]
#
# <slug> as in setup-worktree.sh: the issue folder name under .claude/issues/
# (id prefix may be omitted if the suffix is unique).
#
# Flags:
#   --force   Remove despite a dirty tree AND delete the branch regardless of
#             spec status.
#
# Exit codes:
#   0  worktree removed (branch deleted or kept as reported)
#   1  guard violation (dirty tree, path not a registered worktree)
#   2  usage or environment error

set -uo pipefail

slug_arg=""
force=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) echo "error: unknown flag: $arg" >&2; exit 2 ;;
        *)
            if [ -n "$slug_arg" ]; then
                echo "usage: scripts/teardown-worktree.sh <slug> [--force]" >&2
                exit 2
            fi
            slug_arg="$arg"
            ;;
    esac
done
if [ -z "$slug_arg" ]; then
    echo "usage: scripts/teardown-worktree.sh <slug> [--force]" >&2
    exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 2
fi

primary=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
if [ -z "$primary" ] || [ ! -d "$primary" ]; then
    echo "error: cannot resolve the primary worktree" >&2
    exit 2
fi

# Same slug resolution as setup-worktree.sh; if the issue folder is already
# gone (archived), fall back to the argument verbatim — the worktree path may
# still exist, only the spec status is then unknowable.
issues_dir="$primary/.claude/issues"
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
        exit 1
    fi
fi
[ -z "$slug" ] && slug="$slug_arg"

project=$(basename "$primary")
target="$(dirname "$primary")/${project}-${slug}"

if ! git worktree list --porcelain | grep -Fxq "worktree $target"; then
    echo "error: $target is not a registered worktree" >&2
    exit 1
fi

if [ -d "$target" ]; then
    dirty=$(git -C "$target" status --porcelain 2>/dev/null || true)
    if [ -n "$dirty" ] && [ $force -eq 0 ]; then
        echo "error: worktree is dirty — commit, stash, or pass --force:" >&2
        printf '%s\n' "$dirty" | sed 's/^/       /' >&2
        exit 1
    fi
fi

# No array expansion here: empty-array "${a[@]}" under set -u breaks on the
# bash 3.2 that macOS ships at /bin/bash.
if [ $force -eq 1 ]; then
    git worktree remove --force "$target"
else
    git worktree remove "$target"
fi
if [ $? -ne 0 ]; then
    echo "error: git worktree remove failed" >&2
    exit 2
fi
echo "worktree removed: $target"

branch="issue/$slug"
if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "no branch $branch — nothing to delete"
    exit 0
fi

spec="$issues_dir/$slug/spec.md"
status=""
if [ -f "$spec" ]; then
    status=$(awk '/^---$/{c++; next} c==1 && /^status:/{print $2; exit}' "$spec")
fi

if [ "$status" = "done" ] || [ $force -eq 1 ]; then
    # -D, not -d: squash-merged branches are never "merged" in git's view.
    if git branch -D "$branch" >/dev/null; then
        echo "branch $branch deleted"
    else
        echo "error: could not delete $branch" >&2
        exit 2
    fi
else
    if [ -z "$status" ]; then
        echo "branch $branch kept — no spec found at $spec to prove the issue is done"
    else
        echo "branch $branch kept — spec status is '$status', not 'done' (issue not merged yet)"
    fi
fi
