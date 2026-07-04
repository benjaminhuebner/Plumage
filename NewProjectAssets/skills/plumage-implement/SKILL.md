---
name: plumage-implement
description: This skill should be used when the user runs `/plumage-implement [slug]`, asks to "start implementing issue NNNN", "continue the run", or "resume after the crash". Takes an approved spec and turns it into commits on an issue branch, ending with `PR.md` and status `waiting-for-review`. Fresh-starts from `approved`, resumes from `in-progress`, runs the per-task loop, runs the pre-commit gate, writes PR.md. Do NOT use to merge, push, or open a remote PR — those are separate operations. Do NOT use when the issue is `draft` + `feature` (run `/plumage-plan` first) or already `waiting-for-review` / `done`.
argument-hint: "[slug]"
user-invocable: true
disable-model-invocation: true
---

Plumage-implement is the implementation half of Plumage's workflow. Each step is tracked in `<bundle>/runs/<slug>.json` (inside the project's `*.plumage` bundle) so the work survives crashes. Three scripts carry the run mechanics — invoke them with their full repo-relative path so the permission allowlist matches:

- `.claude/skills/plumage-implement/scripts/start-run.sh <slug>` — starts or resumes the run (queue, branch, run-state, status flip) in one call.
- `.claude/skills/plumage-implement/scripts/complete-task.sh <slug>` — completes one task (gate, evidence, spec tick, run-state) in one call.
- `.claude/skills/plumage-implement/scripts/finish-run.sh <slug>` — flips the spec to `waiting-for-review` and archives the run-state.

## Standalone usage

This skill works without the Plumage app: invoke `/plumage-implement <slug>` directly from a `claude` REPL session in the project root. The slug is the folder name under `.claude/issues/` (e.g. `00051-general-improvements`). All state is file-based; no running Plumage instance is required.

## Step 0: Find and activate matching skills and agents

Identify the task surface — the domains and tooling this issue touches — from the spec and the request. Then invoke every installed skill (Skill tool) and subagent (Agent tool) whose *description* matches that surface, before real work begins; the `/plumage-*` slash command doesn't trip plugin auto-routers (Axiom and similar), so this routing is manual. Match on description, not name; re-scan when work reveals a new domain. No match → continue.

## Round-trip discipline

Wall-clock cost is dominated by model round-trips, not tool time. Default habits for the whole run:

- Batch independent tool calls into one response — read three files in one go, not in three turns.
- Delegate broad exploration ("where is X handled?", "which conventions do these files share?") to an Explore subagent and keep only the digest in context; read known files directly, in narrow line ranges.
- Re-read nothing the context already holds.
- Chain bookkeeping into single Bash calls — the per-task loop is one chained call, not 5–7 separate ones.
- Front-load every interaction (see below); a mid-loop question or permission prompt can stall the run for hours.

Ground every progress claim in a tool result from this session: report only what you can point to evidence for, and if something is not yet verified, say so explicitly. If tests fail, say so with the output; if a step was skipped, say that.

## Decide the entry point

The argument is either the issue's folder name (slug) or **inlined issue content** — the default non-feature implement template injects the contents of `prompt.md` and `spec.md` instead of the slug. Resolve it first:

- `.claude/issues/<argument>/` exists → it is the slug; continue below.
- Otherwise treat the argument as inlined content. Locate the spec frontmatter inside it (the block carrying `id:`, `branch:`, `status:`, `type:`) and resolve the folder from it: strip the `issue/` prefix from `branch`, or pad `id` to the project's `issueIdPadding` (default 5) and glob `.claude/issues/<padded>-*`. The on-disk `spec.md` stays the source of truth for status, task ticks, and `mergeSubject` — the inlined text is upfront context only and may be stale by the time the run starts.
- Neither an existing folder nor parseable frontmatter → stop and ask which issue is meant.
- `<slug>` omitted entirely → list open issues (status `approved` or `in-progress`) and let the user pick one.

Read `.claude/issues/<id-padded>-<slug>/spec.md`. `start-run.sh` enforces the status dispatch (`approved`/`in-progress` proceed, `draft`+`chore`/`spike` proceeds without a plan, everything else exits 6 with the right next step) — but read the spec content yourself first; the brief plan below needs it.

## Start the run

Everything that needs the user happens **before** the run mechanics, never mid-loop:

1. **Brief plan** (fresh starts only — a resume skips this). Restate the spec's technical approach in 2–3 sentences: which files/modules will be touched, the architectural choice for this issue, and anything that looked clear in the spec but is ambiguous now that the code is in front of the agent. If something is genuinely unclear — a question whose answer changes the implementation — ask now. Do not guess.
2. **Front-load interaction.** Ask every clarifying question the brief plan surfaced. If any task's verification will need pixels or real HID (see `references/verification.md`), call computer-use `request_access` for the app under test now.
3. **Chore/spike without a task list:** if the spec has no unchecked `## Tasks` yet, derive the tasks from the spec/prompt and write them into the spec first (ordered checkboxes, one commit each) — `start-run.sh` refuses a spec without tasks, and the loop needs them.
4. **Start:**

    ```bash
    .claude/skills/plumage-implement/scripts/start-run.sh <slug>
    ```

    One call does all of it: dirty-tree check, same-slug guard across all worktrees, FIFO queue for this checkout, branch checkout/creation from the configured default branch, run-state write (fresh or resume — on resume the spec's task ticks are authoritative and `agentPid` is re-bound to this session), queue-entry removal, spec flip to `in-progress`. Exit codes:

    - `0` — run started; the output names the next task number.
    - `4` — still queued behind another run in this checkout. Re-invoke the same command until granted (a queue wait prints the parallel alternative: `setup-worktree.sh <slug>`). Do not end the turn while queued.
    - `5` — dirty working tree. Stop and ask the user: stash, commit, or discard. Never carry dirty state onto the issue branch.
    - `3` — this slug is already running or queued elsewhere. Stop; the issue is taken.
    - `6` — wrong status (message names the right next step, e.g. `/plumage-plan` first).

The run-state file at `<bundle>/runs/<slug>.json` is how the run survives crashes; see `references/run-state-schema.md` for the schema and field ownership. The scripts own all routine writes: `start-run.sh` the initial document, `complete-task.sh` the per-task updates, `run-phase.sh` the exceptional phases (below), `finish-run.sh` the archive. Never edit the file by hand and never touch the Plumage-owned fields (`plumagePid`, `plumageHeartbeatAt`, `agentLastOutputAt`, `lastUserVisibleAction`).

### Review-fix rounds (Request Changes)

Plumage's "Request Changes" review action appends one `- [ ] Review fix: <file>:<line> — <comment>` task per finding, flips the spec back to `in-progress`, and relaunches this skill. `start-run.sh` handles the bookkeeping (counters from the spec's ticks, fresh `headBeforeRun` when the old run-state was archived). Everything else is the normal loop: one gate + one commit per review-fix task (evidence upserts into the existing `evidence.json`), final gate, then **rewrite** PR.md (replace, don't append — the reviewer reads it fresh), back to `waiting-for-review`.

## Turn discipline (Stop hook)

A Stop hook blocks the turn from ending while this session owns an unfinished run or queue entry. The only legitimate ways to end the turn mid-run:

- **Task failed twice, cause unclear:** `.claude/skills/plumage-implement/scripts/run-phase.sh <slug> "failed at task <n>"`, then report what failed, where, and what was tried.
- **Blocked on a decision only the user can make:** `.claude/skills/plumage-implement/scripts/run-phase.sh <slug> "needs-input: <one-line question>"`, then ask the one focused question and stop. On the user's answer, continue the loop (set the phase back by completing the next task as usual).
- **Run finished:** the Finish section below.

Anything else — plans, summaries, promises about work not yet done — is an early stop; keep working instead.

## Per-task loop

For each unchecked task in the spec, in order:

1. **Implement.** Make the code changes the task describes. Read the spec section for context. Stay inside the task's scope — if a related change is needed, finish the current task first, then add a new task to the spec rather than silently expanding. Verify per the ladder in `references/verification.md`: tests first, AX assertions + marker files for functional wiring, `RenderPreview` for static looks, pixels only where pixels are the claim.
2. **Complete in one chained call:**

    ```bash
    .claude/skills/plumage-implement/scripts/complete-task.sh <slug> && git add <file> <file>... && git commit -m "<imperative single-line message>"
    ```

    `complete-task.sh` chains the bookkeeping: branch assert → evidence attempts-increment → default gate (`--wait=1800 --close-instances`; it forwards `--first-commit` on the run's first commit, `--skip-build` when an earlier step already built via a higher-fidelity tool, `--full` if explicitly wanted) → evidence pass-record upsert → spec task tick → one atomic run-state write. Which task it completes is derived from run-state + commit count, so it is idempotent: a re-run after a hook-blocked commit re-gates the fixed tree, skips the already-done tick, and repeats the same run-state write.
    - `git add` and `git commit` stay **literal** in the chained command — the git-policy hooks match on command text and must keep firing. Stage only the files this task touched; **never** `git add -A` (unrelated dirty state must not ride along).
    - Commit message: imperative single line, present tense, no period, describes the result.
    - Worktree caveat: in a secondary worktree, run `git commit` as its own call after the chain — the review hook scans the primary checkout for chained forms.
    - A task whose changes live entirely in untracked files (e.g. only `.claude/` in a project where it is untracked) still commits: `git commit --allow-empty -m "…"`. The one-commit-per-task rhythm is what makes the re-run detection in `complete-task.sh` work.
    - Gate expectations: fast default gate (~15 s warm) behind every commit — build (zero warnings), tests minus `.integration`/`*UITests`, lint, secret scans. A new test added in this task must be green; existing tests must not regress. For a docs-only task build/test are a fast no-op — still run the chain. A `waiting for gate lock held by PID <n>` line is normal (parallel worktree run), not a failure.
3. **On fail** (any non-zero link in the chain):
    - Gate failure: try once more, applying whatever fix the build/test output points to. Hook-blocked commit: fix what the hook flagged, then re-run the same chained command — idempotent, no double tick.
    - Still failing → stop via the Turn-discipline path: `run-phase.sh <slug> "failed at task <n>"`, tell the user what failed, where, and what was tried. Do not commit broken code. Do not proceed to the next task.

## Verification evidence

Both `complete-task.sh` modes record what the gates actually proved into `.claude/issues/<slug>/evidence.json` (per-task and final-gate records: `attempts`, `passedAt`, `head`, `flags` — written atomically by the scripts, never by hand). Plumage's PR tab and `/plumage-review` read it. Evidence is informative only: a write failure warns but never fails the task, and the merge button never depends on it.

## Final gate (`--final-gate`)

After the last task, before PR.md:

```bash
.claude/skills/plumage-implement/scripts/complete-task.sh <slug> --final-gate
```

This runs the gate with `--full --wait=1800 --close-instances` (no spec tick, no task counters), records the run-level `finalGate` evidence record, and advances the run-state phase to `"writing PR.md"`. The default gate already ran behind every commit; this single full pass adds the `.integration` suites and the swift-format full-tree sweep (target ≤ 4 min, typically far less warm). See `references/precommit-gate.md` for the rationale per check.

`--close-instances` matters: a running instance of the app under test wedges xcodebuild's test launch. An instance that *hosts the gate itself* (embedded session) is never killed — the test step skips with an explicit reason; run gates from a terminal session when dogfooding the app on itself.

Any failure stops the run (via `run-phase.sh` + report); nothing is rolled back, the user decides. For `spike` issues the gate is optional — skip if the spec sets `skipPreCommitGate: true` in frontmatter.

## Verify "Done when"

Before writing PR.md, walk the spec's `## Done when` checkboxes one by one. For each criterion: verify it against evidence from this run (a test in the gate, an AX assertion, a preview, a pixel pass — climb the ladder in `references/verification.md`; for several app-visible claims at once use the acceptance subagent described there). Tick a criterion only with evidence in hand. A criterion that cannot be verified stays unchecked and is listed in PR.md's Notes with the reason — an honest gap beats a hollow tick.

## Write PR.md

Write `.claude/issues/<id-padded>-<slug>/PR.md` with these sections:

- **Summary** — what this PR does, two or three sentences. Describe the result, do not restate the spec.
- **Diff stats** — output of `git diff --stat <defaultBranch>...issue/<slug>`.
- **Commits** — chronological list, subject + short hash (7 chars).
- **How to test** — concrete steps a reviewer can run to verify it works. Include the commands, what to look at, and what "passes" means. Reproducible from `git checkout issue/<slug>` alone.
- **Notes** — anything surprising, anything deferred, any unverified Done-when criterion with the reason.

In the same step, set `mergeSubject` in the spec frontmatter (add the field if absent, overwrite if present): a one-line imperative English summary of the whole branch, following the commit-message convention. No issue id or slug, no merge mechanics, no trailing period — e.g. `mergeSubject: Add squash mode to issue merge`.

## Record what was learned

Before finishing, check:

- Non-obvious technical decision in this run (library swap, architecture call, deliberately-not-doing-X)? → one dated entry in `.claude/docs/decisions.md` under **Did**, linking to the issue slug or a commit hash. **Keep it to ~3 sentences** — the entry records the decision and its why; implementation detail lives in PR.md and the commits. Old **Did** entries rotate to `decisions-archive.md`; always append to `decisions.md` itself.
- A direction deliberately rejected during the run? → one dated entry under **Won't (and why)**, same length discipline.
- Library quirk, perf surprise, refactor candidate? → one line in `.claude/docs/notes.md`.

If both files end up untouched after a non-trivial issue, ask the user once: "Nothing went into decisions or notes — did I really learn nothing?" If they confirm, move on.

## Finish

```bash
.claude/skills/plumage-implement/scripts/finish-run.sh <slug>
```

One call: flips the spec to `waiting-for-review` (with `updated:` bumped), then enriches the run-state with `finishedAt` + `outcome: completed` and archives it to `<bundle>/runs/history/` — the file leaving the top level of `runs/` is the completion signal Plumage's notifier keys on, and what tells the Stop hook the turn may end. Never plain-delete the run-state. Then print one line: `Issue <id-padded>-<slug> ready for review.`

## Parallel runs

Two implement runs on disjoint issues can proceed concurrently — **one run per git worktree**, never two in one checkout; `start-run.sh` queues overlapping starts in one checkout FIFO (exit 4). Worktree setup is one call: `.claude/skills/plumage-implement/scripts/setup-worktree.sh <slug>`. Builds and tests still serialize via the shared gate lock (a `waiting for gate lock held by PID <n>` line is normal, not a failure). Provisioning rules, the app-instance verification bracket, teardown, and the caveats live in `references/parallel-runs.md` — read it before any manual worktree setup, cross-worktree debugging, or teardown.

## When to stop and ask

Stop (via the Turn-discipline phases above) under any of these conditions:

- `start-run.sh` exits 3, 5, or 6 (taken slug, dirty tree, wrong status).
- Spec contradicts `PROJECT.md`, a `decisions.md` **Did** entry, or a **Won't** entry.
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
