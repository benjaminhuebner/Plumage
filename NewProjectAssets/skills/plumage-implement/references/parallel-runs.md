# Parallel runs

Two implement runs on disjoint issues can proceed concurrently — **one run per git worktree**, never two in one checkout (they would fight over branch, index, and working tree). Overlapping starts in one checkout don't error: `start-run.sh` queues the later run FIFO (exit 4, re-invoke). True parallelism needs a worktree, and setup is one call:

```bash
.claude/skills/plumage-implement/scripts/setup-worktree.sh <slug>
```

It creates `../<project>-<slug>` detached from the default branch, provisions `.claude/` and the `*.plumage` bundle for the repo's layout, and prints the next steps (`cd` there, `claude`, `/plumage-implement <slug>`). The provisioning rules it enforces — binding for any manual setup too:

- **Never symlink the bundle.** The bundle resolver glob is symlink-blind, and a shared `runs/` would make every fresh start see the other worktree's run as live. The script copies the bundle without `runs/` and `sessions/`, so each worktree owns its run-state.
- **`.claude/` follows tracked-ness.** Tracked → arrives with the checkout. Untracked → symlinked to the *primary* worktree's copy so spec status flips and PR.md propagate back to where the app and the merge look for them.

## What serializes

Builds and tests never run in parallel. The gate lock is keyed on the repo's common git dir, shared across all worktrees — a later gate prints `waiting for gate lock held by PID <n>` and continues when it frees (the skill passes `--wait=1800`, so a queue of runs plus a cold-worktree full build doesn't hit the default timeout). Implementation work between gates runs fully in parallel.

**App-instance verification** (manual launch, AX/computer-use driving, screenshots) is bracketed by the same lock so parallel gates queue instead of killing the instance mid-verification — the bracket, launch rules, and recipes live in `references/verification.md`.

## Caveats

- `--close-instances` kills running instances of the app under test by bundle name, globally — including a manually launched verification instance from the other worktree (unless it holds the exclusive lock). Inherent to the shared bundle ID; relaunch after the gate.
- Docs append race: re-read `decisions.md`/`notes.md` immediately before appending — the Edit tool's stale-file check makes the race self-healing; a residual squash-merge conflict is a trivial keep-both.
- A fresh worktree starts with cold DerivedData — its first gate pays a full build.
- A branch checked out in one worktree cannot be checked out in another; the error on `start-run.sh` is the desired protection (another run owns that branch). `setup-worktree.sh` refuses such a slug up front.
- After merge: `.claude/skills/plumage-implement/scripts/teardown-worktree.sh <slug>` removes the worktree (refuses on a dirty tree) and deletes `issue/<slug>` only when the spec status is `done` — squash merges leave no git ancestry to prove "merged"; the spec status is the source of truth. `--force` overrides both guards.
