---
name: plumage-implement
description: This skill should be used when the user runs `/plumage-implement [slug]`, asks to "start implementing issue NNNN", "continue the run", or "resume after the crash". Takes an approved spec and turns it into commits on an issue branch, ending with `PR.md` and status `waiting-for-review`. Fresh-starts from `approved`, resumes from `in-progress`, runs the per-task loop, runs the pre-commit gate, writes PR.md. Do NOT use to merge, push, or open a remote PR — those are separate operations. Do NOT use when the issue is `draft` + `feature` (run `/plumage-plan` first) or already `waiting-for-review` / `done`.
user-invocable: true
disable-model-invocation: true
---

Plumage-implement is the implementation half of Plumage's workflow. Each step is tracked in `<bundle>/runs/<slug>.json` (inside the project's `*.plumage` bundle) so the work survives crashes.

## Standalone usage

This skill works without the Plumage app: invoke `/plumage-implement <slug>` directly from a `claude` REPL session in the project root. The slug is the folder name under `.claude/issues/` (e.g. `00051-general-improvements`). All state is file-based; no running Plumage instance is required.

## Step 0: Find and activate matching skills and agents

Identify the task surface — what domains and tooling this issue actually touches — from the spec, the user's request, or the issue description. Then scan installed skills and subagents and invoke every one whose description matches that surface, before any real work begins. The `/plumage-*` slash command doesn't trip plugin auto-routers (Axiom and similar), so the routing is manual.

- Skills via the Skill tool, subagents via the Agent tool.
- Match on description, not name. Invoke when the description covers the task surface; don't invoke speculatively because a name sounds related.
- Re-scan when work reveals a domain that wasn't obvious at the start.

If nothing matches or no relevant plugin is installed, continue — the scan happens regardless, the activation is what's conditional.

## Decide the entry point

The argument is either the issue's folder name (slug) or **inlined issue content** — the default non-feature implement template injects the contents of `prompt.md` and `spec.md` instead of the slug. Resolve it first:

- `.claude/issues/<argument>/` exists → it is the slug; continue below.
- Otherwise treat the argument as inlined content. Locate the spec frontmatter inside it (the block carrying `id:`, `branch:`, `status:`, `type:`) and resolve the folder from it: strip the `issue/` prefix from `branch`, or pad `id` to the project's `issueIdPadding` (default 5) and glob `.claude/issues/<padded>-*`. The on-disk `spec.md` stays the source of truth for status, task ticks, and `mergeSubject` — the inlined text is upfront context only and may be stale by the time the run starts.
- Neither an existing folder nor parseable frontmatter → stop and ask which issue is meant.

Read `.claude/issues/<id-padded>-<slug>/spec.md` and dispatch on frontmatter `status` + `type`:

| Status | Type | Action |
|---|---|---|
| `approved` | any | Fresh start. |
| `in-progress` | any | Resume. |
| `draft` | `feature` | Stop. Tell the user to run `/plumage-plan <slug>` first. |
| `draft` | `chore` / `spike` | Fresh start, no plan required. |
| `waiting-for-review` | any | Stop. This issue is past implementation. |
| `done` | any | Stop. |

If `<slug>` is omitted at invocation: list open issues (status `approved` or `in-progress`) and let the user pick one.

## The run-state file

The run-state file at `<bundle>/runs/<slug>.json` is how the run survives crashes. Resolve `<bundle>` by globbing the project root — `bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)` (the `! -name '.*'` skips any legacy hidden `.plumage` dotfolder). See `references/run-state-schema.md` for the full schema, who writes which field, the glob convention, and the atomic-write protocol. Key invariants:

- `runs/` lives inside the committable bundle but is gitignored, so run-state never enters git.
- All writes are atomic (`.tmp` + `rename`). Never write the file in place.
- Plumage writes `plumagePid`, `plumageHeartbeatAt`, `agentLastOutputAt`, and `lastUserVisibleAction`. The skill must not touch those.
- The skill writes `kind`, `runId`, `issue`, `startedAt`, `agentPid`, `phase`, `lastProgressAt`, `branch`, `headBeforeRun`, `lastCompletedTask`, `totalTasks`.

## Fresh start

1. **Check the working tree.** Run `git status`. If there are uncommitted changes, stop and ask the user — stash, commit, or discard — before continuing. Do not carry dirty state onto the issue branch.
2. **Check for a live run in this checkout.** Scan `<bundle>/runs/*.json` for another implement run whose `agentPid` is alive. Treat a missing, zero, or non-numeric `agentPid` as dead — `kill -0 0` probes the caller's own process group and always succeeds, so validate before probing. If a live run exists, stop: two implement runs must not share a checkout (they would fight over branch, index, and working tree). Point the user to the worktree workflow (see "Parallel runs"). Entries with a dead `agentPid` are crash leftovers and don't block.
3. Read `git.defaultBranch` from `<bundle>/config.json` (default `main`).
4. Capture `headBeforeRun = git rev-parse <defaultBranch>`.
5. Write the initial run-state file with `phase: "starting"`, `lastCompletedTask: 0`, `totalTasks` set to the count of unchecked tasks in the spec's `## Tasks` section, and `agentPid` set to the session PID, captured as `ps -o ppid= -p $$` — the long-lived `claude` process that owns this session. Never write `$$` itself: each Bash tool call runs in a fresh shell that is dead by the next call, so `$$` would make this run look crashed to step 2 of a parallel start.
6. Branch: `git checkout -b issue/<slug> <defaultBranch>` — one command, no checkout of `<defaultBranch>` first. This is what makes fresh starts work in a secondary worktree, where `<defaultBranch>` is typically checked out in the primary and `git checkout <defaultBranch>` would fail. If `issue/<slug>` already exists, check it out instead.
7. Set spec frontmatter `status: in-progress`, `updated:` to now.
8. **Brief plan.** Before Task 1, restate the spec's technical approach in 2–3 sentences:
    - Which files/modules will be touched.
    - The architectural choice for this issue — if the spec pins it down, confirm; if the spec leaves room, state the choice now.
    - Anything that looked clear in the spec but is ambiguous now that the code is in front of the agent.

    If something is genuinely unclear — not slightly ambiguous, but a question whose answer changes the implementation — stop and ask before starting Task 1. Do not guess.

## Resume

1. Spec status is already `in-progress`. Read the run-state file.
2. The spec's task checkboxes are authoritative for the resume position — find the next `- [ ]` task in `## Tasks` and start there. If `lastCompletedTask` in the run-state disagrees with what the spec shows, write the corrected value back so future reads are consistent. The spec is the source of truth; the run-state is a hint we keep up to date.
3. `git checkout issue/<slug>`. Do not re-create the branch.
4. If no run-state file exists but the spec says `in-progress` (e.g., the user did things manually): treat the next unchecked task as the resume point and write a fresh run-state.
5. Skip the brief plan — it ran on the original fresh start.

## Parallel runs

Two implement runs on disjoint issues can proceed concurrently — **one run per git worktree**, never two in one checkout (they would fight over branch, index, and working tree; the fresh-start liveness check enforces this). Setup is one call:

```bash
scripts/setup-worktree.sh <slug>
```

It creates `../<project>-<slug>` detached from the default branch, provisions `.claude/` and the `*.plumage` bundle for the repo's layout, and prints the next steps (`cd` there, `claude`, `/plumage-implement <slug>`). Running it for a second, third, fourth slug yields independent parallel runs. The provisioning rules it enforces — binding for any manual setup too:

- **Never symlink the bundle.** The bundle resolver glob (`find -maxdepth 1 -type d`) is symlink-blind, and a shared `runs/` would make every fresh start see the other worktree's run as live. The script copies the bundle without `runs/` and `sessions/`, so each worktree owns its run-state.
- **`.claude/` follows tracked-ness.** Tracked → it arrives with the checkout, nothing to provision. Untracked → it is symlinked to the *primary* worktree's copy so spec status flips and PR.md propagate back to where the app and the merge look for them (a copied `.claude/` silently loses that propagation).

Manual fallback, for tracked `.claude/` + bundle only — untracked layouts use the script:

```bash
git worktree add --detach ../<project>-<slug> <defaultBranch>
cd ../<project>-<slug>
claude        # separate session, then: /plumage-implement <slug>
```

`--detach` matters: without it the command fails whenever `<defaultBranch>` is checked out in the primary worktree (a branch can only be checked out once per repo). The detached HEAD is fine — fresh start branches explicitly with `git checkout -b issue/<slug> <defaultBranch>`.

Each worktree has its own working tree, index, and checked-out branch; commits land on each run's own `issue/<slug>`, sharing one repository.

**What serializes:** builds and tests never run in parallel. The gate lock is keyed on the repo's common git dir, so it is shared across all worktrees — the later gate prints `waiting for gate lock held by PID <n>` and continues automatically when the lock frees (the skill passes `--wait=1800`, so a queue of N runs plus a cold-worktree full build doesn't hit the 900 s default timeout). Implementation work between gates runs fully in parallel.

**App-instance verification:** any manual launch, computer-use driving, or screenshot session against the app under test is bracketed by the same lock the gates use:

```bash
LOCK_OWNER_PID=$(ps -o ppid= -p $$) scripts/exclusive-lock.sh acquire --wait
# … launch the app, drive it, verify …
# quit the app instance, THEN:
LOCK_OWNER_PID=$(ps -o ppid= -p $$) scripts/exclusive-lock.sh release
```

While the lock is held, parallel gates queue behind it instead of killing the instance (`--close-instances`) or stealing mouse and keyboard focus mid-verification. Quit the instance *before* releasing so the desktop is clean when the next gate fires; release *before* running your own gate — the gate's PID differs from the session PID, so it would queue behind your own exclusive lock. The `LOCK_OWNER_PID` prefix is required in agent sessions: each tool shell dies by the next call, and evaluated in the tool shell the expression yields the long-lived session PID (the same idiom as the run-state `agentPid`).

**Caveats:**

- `--close-instances` kills running instances of the app under test by bundle name, globally — including a manually launched verification instance from the other worktree (unless that verification holds the exclusive lock, see above). Inherent to the shared bundle ID; relaunch after the gate.
- Docs append race: re-read `decisions.md`/`notes.md` immediately before appending — the Edit tool's stale-file check forces a re-read when a parallel run appended in between, so the race is self-healing. If both runs still append between each other's merges, the second squash-merge conflicts; trivial keep-both resolution.
- A fresh worktree starts with cold DerivedData — its first gate pays a full build.
- A branch checked out in one worktree cannot be checked out in another; git's own error on resume is the desired protection (another run owns that branch). `setup-worktree.sh` refuses such a slug up front.
- After merge: `scripts/teardown-worktree.sh <slug>` removes the worktree (refuses on a dirty tree) and deletes `issue/<slug>` only when the spec status is `done` — squash merges leave no git ancestry to prove "merged", the spec status is the source of truth. `--force` overrides both guards.

## Per-task loop

For each unchecked task in the spec, in order:

1. Update run-state: `phase: "running task <n>"`, `lastProgressAt` to now.
2. **Implement.** Make the code changes the task describes. Read the spec section for context. Stay inside the task's scope — if a related change is needed, finish the current task first, then add a new task to the spec rather than silently expanding.
3. **Default gate.** Run `scripts/precommit-gate.sh --wait=1800 --close-instances` (add `--first-commit` on this run's first commit). `--wait=1800` queues behind a gate from a parallel worktree run instead of erroring — a `waiting for gate lock held by PID <n>` line is normal, not a failure. The fast default gate is the per-task standard behind every commit (~15 s): it builds, runs the test suite minus `.integration`/`*UITests` suites, lints, and scans for secrets. Zero warnings is compiler-enforced (`SWIFT_TREAT_WARNINGS_AS_ERRORS`). A new test added in this task must be green; existing tests must not regress. If an earlier step already built via a higher-fidelity tool, pass `--skip-build`. For a non-code task (docs only) the gate's build/test are a fast no-op — still run it.
4. **On pass:**
    - **Branch assert.** `git branch --show-current` must print exactly `issue/<slug>`. On mismatch, stop: set run-state `phase: "failed at task <n>"` and tell the user the checkout was switched underneath the run (an app merge on an old build, or a manual `git checkout`) — never commit onto a foreign branch.
    - Tick the task and bump `updated:` in one shot: `scripts/spec-task-tick.py .claude/issues/<id-padded>-<slug>/spec.md --task 1`. The script counts only unchecked tasks under `## Tasks`, ignores `[ ]` inside fenced code blocks and other sections, and writes atomically. Calling it with `--task 1` always means "the next unchecked one".
    - Stage only the files this task touched: `git add <file> <file>...`. **Never** `git add -A` — unrelated dirty state (stale build artifacts, a config edit from another session) must not ride along in the commit.
    - Commit: `git commit -m "<imperative single-line message>"`. Present tense, no period, describes the result.
    - Update run-state: `lastCompletedTask: <n>`, `lastProgressAt` to now.
5. **On fail:**
    - Try once more, applying whatever fix the build/test output points to.
    - Still failing → stop. Run-state: `phase: "failed at task <n>"`. Tell the user what failed, where, and what was tried. Do not commit broken code. Do not proceed to the next task.

## Final gate (`--full`)

After the last task, before PR.md. Update run-state phase → `"pre-commit-gate"`.

```bash
scripts/precommit-gate.sh --full --wait=1800 --close-instances
```

The default gate already ran behind every commit; this single `--full` pass adds the `.integration` suites and the swift-format full-tree sweep — the slow, real-I/O checks worth running once at the end (target ≤ 4 min, typically far less on a warm cache). Seven checks total: build, tests, SwiftLint, swift-format, untracked-secret-files, hardcoded-secret-in-diff, and (with `--first-commit`) `.gitignore` sanity. See `references/precommit-gate.md` for the rationale per check and what failures mean.

`--close-instances` matters: a running instance of the app under test (a leftover `<app>.app`, or an Xcode Run/debug session held under `debugserver`) wedges xcodebuild's test launch into a multi-minute hang. With the flag the gate closes it (and a holding debugserver) before testing; without it, a running instance makes the gate skip the whole test step — on a TTY it prompts to close instead.

Any failure stops the run; nothing is rolled back, the user decides. For `spike` issues the gate is optional — skip if the spec sets `skipPreCommitGate: true` in frontmatter.

## Write PR.md

Update run-state phase → `"writing PR.md"`. Write `.claude/issues/<id-padded>-<slug>/PR.md` with these sections:

- **Summary** — what this PR does, two or three sentences. Describe the result, do not restate the spec.
- **Diff stats** — output of `git diff --stat <defaultBranch>...issue/<slug>`.
- **Commits** — chronological list, subject + short hash (7 chars).
- **How to test** — concrete steps a reviewer can run to verify it works. Include the commands, what to look at, and what "passes" means. Reproducible from `git checkout issue/<slug>` alone.
- **Notes** — anything surprising, anything deferred, anything the reviewer should know.

In the same step, set `mergeSubject` in the spec frontmatter (add the field if absent, overwrite if present): a one-line imperative English summary of the whole branch, following the commit-message convention. It becomes the squash-commit subject when the issue is merged. No issue id or slug, no merge mechanics ("squash", "merge branch"), no trailing period — e.g. `mergeSubject: Add squash mode to issue merge`.

## Record what was learned

Before finishing, check:

- Non-obvious technical decision in this run (library swap, architecture call, deliberately-not-doing-X)? → one dated line in `.claude/docs/decisions.md` under **Did**, linking to the issue slug or a commit hash.
- A direction deliberately rejected during the run? → one dated line in `.claude/docs/decisions.md` under **Won't (and why)**.
- Library quirk, perf surprise, refactor candidate? → one line in `.claude/docs/notes.md`.

If both files end up untouched after a non-trivial issue, ask the user once: "Nothing went into decisions or notes — did I really learn nothing?" If they confirm, move on.

## Finish

1. Set spec frontmatter `status: waiting-for-review`, `updated:` to now.
2. Delete `<bundle>/runs/<slug>.json`.
3. Print one line: `Issue <id-padded>-<slug> ready for review.`

## When to stop and ask

Stop and ask under any of these conditions:

- Spec status is `draft` and type is `feature` (`/plumage-plan` must run first).
- Spec status is `waiting-for-review` or `done` (this issue is past implementation).
- Spec contradicts `PROJECT.md`, a `decisions.md` **Did** entry, or a **Won't** entry.
- Working tree is dirty on Fresh start.
- A task fails twice and the cause is not clear from build/test output.
- The pre-commit gate fails on something outside the scope of any single task.
- A blocker emerges that requires a decision the spec does not cover.
- The implementation as written would require changes outside the task list.

## What this skill does NOT do

- Does not push to a remote. Pushing is manual after merge.
- Does not open a GitHub/GitLab PR. The PR view is local.
- Does not merge. That is a separate operation.
- Does not archive after merge.
- Does not squash, rebase, or rewrite history. Each task is its own commit; if a clean log is wanted, the user squashes on merge.
- Does not clear context mid-run; that is the orchestrator's job before invoking the skill.
- Does not run in Plan Mode — Plan Mode blocks Write/Edit. Only `/plumage-plan` is Plan-Mode-bound.
