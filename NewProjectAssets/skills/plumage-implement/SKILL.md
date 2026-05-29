---
name: plumage-implement
description: This skill should be used when the user runs `/plumage-implement [slug]`, asks to "start implementing issue NNNN", "continue the run", or "resume after the crash". Takes an approved spec and turns it into commits on an issue branch, ending with `PR.md` and status `waiting-for-review`. Fresh-starts from `approved`, resumes from `in-progress`, runs the per-task loop, runs the pre-commit gate, writes PR.md. Do NOT use to merge, push, or open a remote PR — those are separate operations. Do NOT use when the issue is `draft` + `feature` (run `/plumage-plan` first) or already `waiting-for-review` / `done`.
user-invocable: true
disable-model-invocation: true
---

Plumage-implement is the implementation half of Plumage's workflow. Each step is tracked in `.plumage/runs/<slug>.json` so the work survives crashes.

## Standalone usage

This skill works without the Plumage app: invoke `/plumage-implement <slug>` directly from a `claude` REPL session in the project root. The slug is the folder name under `.claude/issues/` (e.g. `00051-general-improvements`). All state is file-based; no running Plumage instance is required.

## Step 0: Find and activate matching skills and agents

Identify the task surface — what domains and tooling this issue actually touches — from the spec, the user's request, or the issue description. Then scan installed skills and subagents and invoke every one whose description matches that surface, before any real work begins. The `/plumage-*` slash command doesn't trip plugin auto-routers (Axiom and similar), so the routing is manual. This project's primary domains and tooling are: <<<SKILL_KEYWORDS>>> — use these as the starting descriptions to match installed skills and agents against.

- Skills via the Skill tool, subagents via the Task tool.
- Match on description, not name. Invoke when the description covers the task surface; don't invoke speculatively because a name sounds related.
- Re-scan when work reveals a domain that wasn't obvious at the start.

If nothing matches or no relevant plugin is installed, continue — the scan happens regardless, the activation is what's conditional.

## Decide the entry point

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

The run-state file at `.plumage/runs/<slug>.json` is how the run survives crashes. See `references/run-state-schema.md` for the full schema, who writes which field, and the atomic-write protocol. Key invariants:

- All writes are atomic (`.tmp` + `rename`). Never write the file in place.
- Plumage writes `plumagePid`, `plumageHeartbeatAt`, `agentLastOutputAt`, and `lastUserVisibleAction`. The skill must not touch those.
- The skill writes `kind`, `runId`, `issue`, `startedAt`, `agentPid`, `phase`, `lastProgressAt`, `branch`, `headBeforeRun`, `lastCompletedTask`, `totalTasks`.

## Fresh start

1. **Check the working tree.** Run `git status`. If there are uncommitted changes, stop and ask the user — stash, commit, or discard — before continuing. Do not carry dirty state onto the issue branch.
2. Read `git.defaultBranch` from `.plumage/config.json` (default `main`).
3. Capture `headBeforeRun = git rev-parse <defaultBranch>`.
4. Write the initial run-state file with `phase: "starting"`, `lastCompletedTask: 0`, and `totalTasks` set to the count of unchecked tasks in the spec's `## Tasks` section.
5. Branch: `git checkout <defaultBranch> && git checkout -b issue/<slug>`. If `issue/<slug>` already exists, check it out instead.
6. Set spec frontmatter `status: in-progress`, `updated:` to now.
7. **Brief plan.** Before Task 1, restate the spec's technical approach in 2–3 sentences:
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

## Per-task loop

For each unchecked task in the spec, in order:

1. Update run-state: `phase: "running task <n>"`, `lastProgressAt` to now.
2. **Implement.** Make the code changes the task describes. Read the spec section for context. Stay inside the task's scope — if a related change is needed, finish the current task first, then add a new task to the spec rather than silently expanding.
3. **Build.** Run `swift build` for SwiftPM; for Xcode projects, use the matching `mcp__xcodebuildmcp__*` tool (use MCP discovery to find the right one for the project type). Zero warnings counts as failure — fix them in this task. Silencing a warning with `// swiftlint:disable` requires a one-line justification.
4. **Test.** Run the test suite. New tests must be green. Existing tests must not regress. If the project has no tests at all, skip silently.
5. **On pass:**
    - Tick the task and bump `updated:` in one shot: `scripts/spec-task-tick.py .claude/issues/<id-padded>-<slug>/spec.md --task 1`. The script counts only unchecked tasks under `## Tasks`, ignores `[ ]` inside fenced code blocks and other sections, and writes atomically. Calling it with `--task 1` always means "the next unchecked one".
    - Stage only the files this task touched: `git add <file> <file>...`. **Never** `git add -A` — unrelated dirty state (stale build artifacts, a config edit from another session) must not ride along in the commit.
    - Commit: `git commit -m "<imperative single-line message>"`. Present tense, no period, describes the result.
    - Update run-state: `lastCompletedTask: <n>`, `lastProgressAt` to now.
6. **On fail:**
    - Try once more, applying whatever fix the build/test output points to.
    - Still failing → stop. Run-state: `phase: "failed at task <n>"`. Tell the user what failed, where, and what was tried. Do not commit broken code. Do not proceed to the next task.

## Pre-commit gate

After the last task. Update run-state phase → `"pre-commit-gate"`.

```bash
scripts/precommit-gate.sh --first-commit  # only on the first commit of this run
scripts/precommit-gate.sh                  # subsequent runs (no --first-commit)
```

The script runs seven checks: build, tests, SwiftLint, swift-format, untracked-secret-files, hardcoded-secret-in-diff, and (first commit only) `.gitignore` sanity. See `references/precommit-gate.md` for the rationale per check and what failures mean.

Any failure stops the run; nothing is rolled back, the user decides. For `spike` issues the gate is optional — skip if the spec sets `skipPreCommitGate: true` in frontmatter.

If an earlier task used the MCP build tool with higher-fidelity output, pass `--skip-build` here to avoid re-running the same compile against a clean CLI. The MCP build counts as the gate's build check when it has been used.

## Write PR.md

Update run-state phase → `"writing PR.md"`. Write `.claude/issues/<id-padded>-<slug>/PR.md` with these sections:

- **Summary** — what this PR does, two or three sentences. Describe the result, do not restate the spec.
- **Diff stats** — output of `git diff --stat <defaultBranch>...issue/<slug>`.
- **Commits** — chronological list, subject + short hash (7 chars).
- **How to test** — concrete steps a reviewer can run to verify it works. Include the commands, what to look at, and what "passes" means. Reproducible from `git checkout issue/<slug>` alone.
- **Notes** — anything surprising, anything deferred, anything the reviewer should know.

## Record what was learned

Before finishing, check:

- Non-obvious technical decision in this run (library swap, architecture call, deliberately-not-doing-X)? → one dated line in `.claude/docs/decisions.md` under **Did**, linking to the issue slug or a commit hash.
- A direction deliberately rejected during the run? → one dated line in `.claude/docs/decisions.md` under **Won't (and why)**.
- Library quirk, perf surprise, refactor candidate? → one line in `.claude/docs/notes.md`.

If both files end up untouched after a non-trivial issue, ask the user once: "Nothing went into decisions or notes — did I really learn nothing?" If they confirm, move on.

## Finish

1. Set spec frontmatter `status: waiting-for-review`, `updated:` to now.
2. Delete `.plumage/runs/<slug>.json`.
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
