# Pre-commit gate

The gate runs after the last task in a `/plumage-implement` run, before `PR.md` is written. Same checks are also exposed as Plumage's native "Run Quality Gate" toolbar button (no agent involved). Both paths invoke `scripts/precommit-gate.sh` — the script is the canonical implementation.

## Why a gate at all

Per-task green is necessary but not sufficient. Some failures only appear when the whole branch is considered together: an unused import after a refactor, a SwiftLint rule that's per-file-clean but cross-file violated, a `.env.local` that crept in untracked, a hardcoded test secret that ended up in the diff. The gate catches them once at the end, where fixing them is still cheap.

## The seven checks

For `feature` and `chore` issues, all seven must pass. For `spike` issues, the gate is optional — skip if the spec sets `skipPreCommitGate: true` in frontmatter.

### 1. Build — zero errors, zero warnings

Why zero warnings: warnings often hide real bugs (unreachable code, missing await, deprecated API that's already broken). Treating them as errors here forces the fix while you still understand the change. The rule is editable in `CLAUDE.md` if a project needs to tolerate warnings, but the default is strict.

**How warnings become failures depends on the project setup.** Two paths:

- **Preferred — at compile time.** Plumage's SwiftPM project template sets `.treatAllWarnings(as: .error)` in `Package.swift` (Swift 6.2+, swift-tools-version 6.2). `swift build` then fails the build directly on any warning. The gate's Step 1 sees a non-zero exit code, no log parsing required. For Xcode projects, the equivalent is `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- **Fallback — log scraping.** If the project does not opt into compile-time strictness, `precommit-gate.sh` greps `swift build` / `xcodebuild build` output for `: warning:`. This works for raw `xcodebuild` output but is fragile against pretty-printers (xcbeautify, xcpretty). If the project uses one, pipe to `tee` so the gate can read the raw log.

Silencing a single warning with `// swiftlint:disable <rule>` or `@available(*, deprecated)` requires a one-line justification on the same line or the line above. The justification is what makes the silence reviewable later. For project-wide migration scenarios (e.g., enabling Swift 6 strict concurrency incrementally), use `.treatWarning("DiagnosticGroup", as: .warning)` to downgrade specific groups, and log the decision in `notes.md`.

### 2. Tests — all green

The full test suite must pass. New tests added in this run must be green. Existing tests must not regress. If the project has no tests at all, this step is skipped silently (no failure, no warning).

**Running-instance handling:** a *live* instance of the app under test (a leftover `<app>.app`, or an Xcode Run/debug session held under `debugserver`, stuck in state `SX` and ignoring SIGKILL) wedges xcodebuild's test launch — both the UI-test target and the hosted unit-test runner go through the same launch/testmanagerd coordination — into a multi-minute hang. Before the test step the gate detects a running instance and: with `--close-instances` closes it (incl. the holding debugserver) and runs the full suite; on an interactive TTY it prompts whether to close; non-interactively without the flag it skips the whole test step with a clear message. It never auto-kills non-interactively, because the gate also runs from the app's own "Run Quality Gate" toolbar button and would otherwise self-kill. `/plumage-implement` invokes the gate with `--close-instances`.

A common trap: a test that was already failing before this run will fail the gate now. Don't fix it as a side-effect of this issue — flag it, ask the user, and either add a task for the fix or carry it as a known-broken test with a `notes.md` entry.

### 3. SwiftLint — zero violations across the codebase

Broader than the per-file `lint-swift` hook that runs after each edit. The full-codebase sweep catches things the per-file run can't: unused imports introduced by a refactor, rule violations in files that weren't edited but interact with the new code, custom rules that depend on cross-file state.

### 4. swift-format lint mode

`swift-format lint` checks the codebase against the `.swift-format` config without modifying anything. Different from the `format-swift` PostToolUse hook (which auto-fixes after each edit) — this step catches files the hook skipped or didn't touch.

### 5. `git status` — no untracked secret files

Scan for untracked files matching common secret patterns: `.env`, `.env.local`, `*.key`, `*.pem`, `id_rsa`, `id_ed25519`, `aws-credentials`, `.netrc`. The `block-secret-files` hook prevents *reading* these during the run, but a file that was created by some tool side-effect (a generator, an SDK) can still end up on disk untracked. Catch it before the commit.

If found, the gate stops and lists the paths. The user decides: delete, add to `.gitignore`, or fix the tool that created them.

### 6. `git diff` — no hardcoded secrets in the diff

Regex sweep against the cumulative diff (`git diff <defaultBranch>...HEAD`) for patterns that look like API keys, tokens, or credentials. Same conservative pattern set as the `block-secrets-in-content.sh` hook. False positives are possible — test fixtures, OAuth demos, regex examples — and need to be carved out via a per-project allowlist (Phase 2).

### 7. `.gitignore` sanity — first commit only

Only runs if this is the issue's first commit on the branch. Checks that `.gitignore` covers the basics for the project's stack: `.build/`, `.swiftpm/`, `Package.resolved` (sometimes — depends on whether you check it in), `DerivedData/`, `xcuserdata/`, `*.xcodeproj/project.xcworkspace/xcuserdata/`. Skip on subsequent commits — by then `.gitignore` is settled.

This is a "first commit only" check because a missing `.gitignore` entry on commit 1 has cascading damage (binary blobs in history), but on commit 7 it's just an annoyance. The first-commit-only scope keeps the gate fast on later runs.

## What a failure looks like

The script prints a per-step header (`[1/7] Build...`) followed by `PASS`, `FAIL`, or `SKIP`. On `FAIL`, the next lines are an excerpt of the failing output (last ~20 lines or the specific violation list). The script exits with code 1 on any failure, 0 on full pass. Plumage's native panel parses the per-step lines into ✅/❌; the skill reads the same output as text.

## What the gate does NOT do

- Doesn't auto-fix anything. The gate is diagnosis. Fixes are tasks (added to the spec) or a separate manual pass.
- Doesn't commit. Even on full pass, the gate's job is to validate, not to take the next step.
- Doesn't rerun previously-failed checks differently. If the first run fails on step 3, the second run starts at step 1 again — order matters because step 1's output (build artifacts) may affect step 3.
- Doesn't catch logic bugs. It catches what static analysis + the test suite catch. A correctly-written test that asserts wrong behavior will pass the gate.
