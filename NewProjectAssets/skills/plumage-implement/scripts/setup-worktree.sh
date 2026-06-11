#!/usr/bin/env bash
# setup-worktree.sh — prepare a ready-to-use parallel /plumage-implement worktree.
#
# Creates ../<project>-<slug> detached from the default branch, then provisions
# .claude/ and the *.plumage bundle correctly for the repo's layout:
#   tracked    → nothing to do, they arrive with the checkout (the bundle's
#                runs/ is gitignored and therefore absent — a fresh start
#                treats that as "no live run").
#   untracked  → symlink .claude/ to the PRIMARY worktree's copy (so spec
#                status flips and PR.md propagate back), and copy the bundle
#                excluding runs/ and sessions/ (never symlink the bundle: the
#                resolver glob matches directories only, and a shared runs/
#                would make every fresh start see the other run as live).
#
# Usage:
#   scripts/setup-worktree.sh <slug>
#
# <slug> is the issue folder name under .claude/issues/ (e.g.
# 00042-add-user-auth); the id prefix may be omitted if the suffix is unique.
#
# All guards run before `git worktree add` — a refused setup creates nothing.
#
# Exit codes:
#   0  worktree ready
#   1  guard violation (issue missing, target exists, branch owned elsewhere)
#   2  environment problem (not a git repo, no resolvable *.plumage bundle)

set -uo pipefail

slug_arg="${1:-}"
if [ -z "$slug_arg" ] || [ $# -gt 1 ]; then
    echo "usage: scripts/setup-worktree.sh <slug>" >&2
    exit 2
fi
case "$slug_arg" in
    -h|--help)
        sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 2
fi

# The primary worktree is the first entry of `git worktree list` — invoked
# from a secondary worktree, symlinks and copies must still point there.
primary=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
if [ -z "$primary" ] || [ ! -d "$primary" ]; then
    echo "error: cannot resolve the primary worktree" >&2
    exit 2
fi

# ---- Guard 1: issue folder exists (typo guard) -------------------------------

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
if [ -z "$slug" ]; then
    echo "error: no issue folder matches '$slug_arg' under $issues_dir" >&2
    exit 1
fi

# ---- Guard 2: target path free ------------------------------------------------

project=$(basename "$primary")
target="$(dirname "$primary")/${project}-${slug}"
if [ -e "$target" ]; then
    echo "error: target path already exists: $target" >&2
    exit 1
fi
if git worktree list --porcelain | grep -Fxq "worktree $target"; then
    echo "error: $target is still a registered worktree (git worktree remove it first)" >&2
    exit 1
fi

# ---- Guard 3: issue branch not checked out in another worktree ----------------

branch_owner=$(git worktree list --porcelain \
    | awk -v b="branch refs/heads/issue/$slug" '/^worktree /{w=substr($0, 10)} $0 == b {print w; exit}')
if [ -n "$branch_owner" ]; then
    echo "error: issue/$slug is checked out in $branch_owner — that run owns the issue" >&2
    exit 1
fi

# ---- Resolve provisioning inputs (still before any mutation) ------------------

claude_tracked=0
[ -n "$(git -C "$primary" ls-files .claude | head -1)" ] && claude_tracked=1

# Same resolver glob as the gate; `! -name '.*'` skips a legacy hidden
# .plumage dotfolder, `-type d` means a symlinked bundle is NOT found.
bundle=$(find "$primary" -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
if [ -z "$bundle" ]; then
    echo "error: no *.plumage bundle found in $primary" >&2
    echo "       (a symlinked bundle is invisible to the resolver — it must be a real directory)" >&2
    exit 2
fi
bundle_name=$(basename "$bundle")
bundle_tracked=0
[ -n "$(git -C "$primary" ls-files "$bundle_name" | head -1)" ] && bundle_tracked=1

default_branch=""
if [ -f "$bundle/config.json" ] && command -v jq >/dev/null 2>&1; then
    default_branch=$(jq -r '.git.defaultBranch // empty' "$bundle/config.json" 2>/dev/null || true)
fi
if [ -z "$default_branch" ]; then
    if git show-ref --verify --quiet refs/heads/main; then default_branch=main
    elif git show-ref --verify --quiet refs/heads/master; then default_branch=master; fi
fi
if [ -z "$default_branch" ]; then
    echo "error: cannot determine the default branch (no config.json entry, no main/master)" >&2
    exit 2
fi

# ---- Create the worktree -------------------------------------------------------

# --detach matters: the default branch is typically checked out in the
# primary and a branch can only be checked out once per repo. The fresh
# start branches explicitly with `git checkout -b issue/<slug>`.
if ! git worktree add --detach "$target" "$default_branch"; then
    echo "error: git worktree add failed" >&2
    exit 2
fi

# ---- Provision .claude/ and the bundle ----------------------------------------

if [ $claude_tracked -eq 1 ]; then
    echo ".claude/ is tracked — arrived with the checkout"
else
    ln -s "$primary/.claude" "$target/.claude"
    # A `.claude/` dir-pattern (trailing slash) does not match the symlink, so
    # it would show as untracked and trip every dirty-tree check in the new
    # worktree. info/exclude is shared across worktrees; the slash-less
    # pattern still matches the real directory in the primary.
    common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
    mkdir -p "$common_dir/info"
    if ! grep -qxF '.claude' "$common_dir/info/exclude" 2>/dev/null; then
        echo '.claude' >> "$common_dir/info/exclude"
    fi
    echo ".claude/ untracked — symlinked to $primary/.claude (status/PR.md propagate back)"
fi

if [ $bundle_tracked -eq 1 ]; then
    echo "$bundle_name is tracked — arrived with the checkout"
else
    mkdir "$target/$bundle_name"
    while IFS= read -r entry; do
        name=$(basename "$entry")
        case "$name" in runs|sessions) continue ;; esac
        cp -R "$entry" "$target/$bundle_name/$name"
    done < <(find "$bundle" -mindepth 1 -maxdepth 1)
    mkdir -p "$target/$bundle_name/runs"
    echo "$bundle_name untracked — copied without runs/ and sessions/ (own run-state per worktree)"
fi

resolved=$(find "$target" -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
if [ -z "$resolved" ]; then
    echo "error: provisioning finished but no bundle resolves in $target" >&2
    exit 2
fi

echo
echo "worktree ready: $target"
echo "next steps:"
echo "  cd $target"
echo "  claude"
echo "  /plumage-implement $slug"
