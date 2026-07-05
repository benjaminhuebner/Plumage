# Pre-commit gate

The gate runs in the `/plumage-implement` loop and is also exposed as Plumage's native "Run Quality Gate" toolbar button (no agent involved). Both paths invoke `scripts/precommit-gate.sh` — the script is the canonical implementation. The same numbered output and exit codes serve both.

## Two modes

| Mode | When | Scope | Target wallclock |
|---|---|---|---|
| **default** (no flag) | after every `/plumage-implement` task | skips `.integration`-tagged suites and the swift-format full-tree sweep | ≤ 90 s |
| **`--full`** | once at issue end, before merge-local; Plumage's toolbar button | includes `.integration` suites and the swift-format sweep | ≤ 4 min |

Both modes exclude `*UITests` targets unless `--with-uitests` is passed (UI tests launch the app and are slow + occasionally wedge the test host — they are an explicit, less frequent check). On warm caches the real numbers are far under target (default ~15 s, full ~20 s for Plumage).

The split exists because per-task green needs to be *fast* and *deterministic*: the default gate is the thing standing between each task and its commit. The `--full` gate is the safety net that runs the slow, real-I/O integration suites and the cross-file format sweep once, where the extra minutes are affordable.

## Parallel tracks

The seven checks run as three concurrent tracks; the numbered output is assembled in fixed order afterwards so `[N/7]` stays stable for Plumage's parser.

```
Track A (sequential):  Step 1 build-for-testing  →  Step 2 test (needs artefacts)
Track B (independent): Step 3 SwiftLint --strict (full tree)
                       Step 4 swift-format lint  (--full only)
Track C (independent): Step 5 untracked secrets  Step 6 diff secrets  Step 7 .gitignore
```

Tracks B and C run in the background while track A builds and tests; their results are collected before the summary. Wallclock = max(A, B, C), which in practice is track A — lint and secrets cost a second or two and are effectively free behind the build.

## The gate lock

Two xcodebuild invocations against the same project deadlock over DerivedData/SWBBuildService, so at most one gate runs per repo at a time. The lock is a PID file under `$TMPDIR` (macOS has no `flock`), keyed on a hash of `git rev-parse --path-format=absolute --git-common-dir` — identical across **all worktrees** of one repo, so gates from parallel `/plumage-implement` runs in separate worktrees serialize against each other and against the toolbar button. For a single checkout the behavior is unchanged.

**Acquisition:** the gate writes its PID to a private temp file, then hard-links it to the lock path. `link(2)` is atomic and fails if the target exists, so the lock can never be observed without its owner PID — there is no create-then-write window in which a contender could mistake a slow starter for a crashed owner (the earlier `mkdir`-then-write design had exactly that window).

**Ownership and stale takeover:** on contention the gate reads the owner PID from the lock file; if the owner is dead (`kill -0` fails) or the PID is invalid (zero or non-numeric — `kill -0 0` would probe the gate's own process group), the lock is stale and taken over automatically — a `kill -9`'d gate no longer blocks the next run. Takeover renames the lock aside (`mv`, atomic, so of two concurrent takeovers exactly one wins), re-validates that the renamed file still names the stale owner, and only then deletes it; if the content changed, a faster contender already took over and re-acquired, and the file is moved back. Release is ownership-checked: the EXIT trap removes the lock only while it still contains the releasing gate's own PID, so a completed takeover can't be undone by the previous owner's exit. Locks from the pre-hard-link version of the script (a *directory* with the PID at `<dir>/pid`) are read transparently: a live old-format owner is respected, a dead one taken over — mixed-version contention during an upgrade stays safe. (`ln` onto an existing directory would silently link *into* it, so acquisition re-reads the lock after `ln` and only counts it as acquired when it contains the gate's own PID.)

**Contention with a live owner:**

- default (no flag): fail fast, exit 2, message names the owner PID. This is the toolbar path — Plumage's "Run Quality Gate" button keeps its existing behavior.
- `--wait[=secs]`: print `waiting for gate lock held by PID <n>...`, poll every ~2 s until the lock frees, then run normally. Default timeout 900 s (covers a slow `--full` gate); on timeout, exit 2 naming the owner. `/plumage-implement` passes `--wait` on every gate invocation so parallel worktree runs queue instead of erroring.

**Known limit — PID recycling:** if a stale lock's PID was recycled by an unrelated live process, the lock looks held; `--wait` runs into its timeout and exits 2 naming the PID, and the operator removes the lock file manually. Rare and self-describing, accepted. (The ownership-checked release bounds the damage of a takeover misjudgment: whoever holds the file proceeds, the other party's exit can't delete it.)

## The seven checks

All applicable checks must pass for every issue type. Exception: the gate is optional when the spec sets `skipPreCommitGate: true` in frontmatter (typical for `spike` issues — throwaway exploration code).

### 1. Build — zero errors, zero warnings

Warnings are enforced **at compile time**, not by log-scraping. The Xcode project sets `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` on the app and unit-test targets (for SwiftPM the equivalent is `.treatAllWarnings(as: .error)`). A warning then fails the build directly; the gate just reads the exit code. This is more robust than grepping `: warning:` — an incremental build does not re-emit warnings for files it did not recompile, so the old grep could miss a warning that a clean compile would catch.

Note: set the flag **per target**, never as a global `xcodebuild` command-line override — it would leak into the SPM dependency targets (built with `-suppress-warnings`) and hard-fail with `Conflicting options '-warnings-as-errors' and '-suppress-warnings'`.

Step 1 uses `build-for-testing` so the test bundles compile too and an `.xctestrun` is emitted for step 2's `test-without-building`.

### 2. Tests — all green

Run via the selected test plan (see below). The default mode additionally passes `-skip-testing` for each `.integration`-tagged suite; both modes pass `-skip-testing` for `*UITests` unless `--with-uitests`.

**Running-instance handling:** a *live* instance of the app under test (a leftover `<app>.app`, or an Xcode Run/debug session held under `debugserver`) wedges xcodebuild's test launch — the hosted unit-test runner goes through the same launch/testmanagerd coordination. Before the test step the gate detects a running instance and: with `--close-instances` closes it (incl. the holding debugserver) and runs; on a TTY prompts; non-interactively without the flag SKIPs the whole test step (never auto-kills — the gate also runs from the app's own toolbar and would self-kill). `/plumage-implement` invokes the gate with `--close-instances`.

A test that was already failing before this run will fail the gate now. Don't fix it as a side-effect of the current issue — flag it, ask, and either add a task or carry it as a known-broken test with a `notes.md` entry.

### 3. SwiftLint — zero violations across the codebase

Full-tree `swiftlint --strict --quiet`. Broader than the per-file lint hook: catches unused imports after a refactor, cross-file rule violations, custom rules. Runs in both modes (cheap, and parallel to the build).

### 4. swift-format lint — `--full` only

`swift-format lint --strict` over the tree. Skipped in default mode: the `format-swift` PostToolUse hook already formats every edited file, so a per-commit full-tree sweep is a per-file-rule duplicate with no cross-file value. `--full` keeps it as a safety net against hook-bypass scenarios (manual `git` surgery, an external editor).

### 5. `git status` — no untracked secret files

Scan untracked files for `.env`, `*.key`, `*.pem`, `id_rsa`/`id_ed25519`/`id_ecdsa`, `aws-credentials`, `.netrc`. Catches a secret a tool dropped on disk untracked.

### 6. `git diff` — no hardcoded secrets in the diff

Regex sweep of `git diff <defaultBranch>...HEAD` for well-known key/token prefixes — the same pattern set `block-secrets-in-content.sh` enforces on writes (AKIA…/ASIA…, gh[poasu]_…, sk-…, sk_live/test_…, rk_live/test_…, xox[baprs]-…, AIza…, PEM private-key blocks). Conservative; false positives need a per-project allowlist (future).

### 7. `.gitignore` sanity — first commit only

Only with `--first-commit`. Checks `.gitignore` covers the stack's basics (`.build/`/`.swiftpm/` for SwiftPM, `DerivedData/`/`xcuserdata/` for Xcode). First-commit-only because a missing entry on commit 1 has cascading damage, on commit 7 it's an annoyance.

## Test-plan selection and the `.integration` exclusion

The gate auto-detects test plans by filename from the repo root:

- **default plan** = first `*.xctestplan` that is not `*.Full.xctestplan` (e.g. `Plumage.xctestplan`)
- **full plan** = first `*.Full.xctestplan` (e.g. `Plumage.Full.xctestplan`)
- no plan found → the test step runs unfiltered (today's fallback for a freshly scaffolded project)

Both plans are referenced by the scheme so `-testPlan <name>` resolves.

**Why the plan does not do the `.integration` filtering itself:** xcodebuild does **not** honour Swift Testing tag/test selection inside a `.xctestplan` (`skippedTags` makes the plan unreadable; `skippedTests` by suite name is silently ignored for Swift Testing — both verified). Plan-internal selection only works for XCTest. So the gate excludes integration suites with command-line `-skip-testing:<TestTarget>/<Suite>` flags, **derived dynamically** from the `.tags(.integration)` annotations (grep for the tag, take the first `struct`/`final class` name after it). A newly-tagged suite is excluded automatically — no gate edit. The default plan carries no manual skip list: xcodebuild ignores Swift Testing `skippedTests` by suite name, so a plan-side list would only be dead weight that drifts from the gate. The command-line `-skip-testing` flags are the single source of truth. Pass each `-skip-testing` as a **separate** argument — a single concatenated string only honours the first.

Mark a suite integration with `@Suite("…", .tags(.integration))` when it drives real FSEvents, subprocesses, or long sync waits. These suites also slow *everything* when they run concurrently with the rest (disk + main-actor contention), so excluding them is most of the default gate's speed win.

## `--timing`

Appends per-step `(Xs)` to each result line and a `total: Xs (<mode> mode, warm cache)` trailer before the summary. Plumage's toolbar passes `--timing` and parses the trailer + per-step timings into the Quality-Gate panel. Default (no `--timing`) output stays minimal.

## What a failure looks like

Per-step header `[1/7] Build...` followed by `PASS`, `FAIL`, or `SKIP`. On `FAIL`, the next lines are an indented excerpt of the failing output. Exit 1 on any failure, 0 on full pass, 2 on an environment problem (no git repo, no Swift project). Plumage's panel parses the per-step lines into ✅/❌; the skill reads the same text.

## What the gate does NOT do

- Doesn't auto-fix anything. Diagnosis only; fixes are tasks or a manual pass.
- Doesn't commit. Even on full pass, its job is to validate.
- Doesn't catch logic bugs — only what static analysis + the test suite catch.
