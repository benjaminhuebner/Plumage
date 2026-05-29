# <<<PROJECT_NAME>>>
<<<PROJECT_TAGLINE>>>

## Stack
<<<STACK_SUMMARY>>>

## Reference docs
- `.claude/docs/PROJECT.md` — what this project is and isn't. Read first when context is missing.
- `.claude/docs/decisions.md` — append-only technical history. **Did** (past choices, dated, with spec slug or commit) and **Won't (and why)** (rejected directions, dated). Search both before choosing direction; a "we won't" binds as much as a "we did". If a new spec proposes something **Won't** says no to, flag it before implementing.
- `.claude/docs/notes.md` — library quirks, perf findings, refactor candidates. Future-you bait: *"`SomeLib.parse` panics on empty input"*, *"`UsersController.list` is N+1"*.

If you finished an issue and wrote nothing in either, ask once: did I really learn nothing?

## Communication
- Be direct. If a request is bad or will produce a worse result, say so before doing it.
- One focused question at a time when something's unclear. Don't bury me in checklists.

## Issues
Issues live in `.claude/issues/<id>-<slug>/spec.md`. Frontmatter is source of truth; `/plumage-plan` and `/plumage-implement` manage `status` — don't edit by hand or create issue files manually (IDs are assigned externally).

## Project layout
<<<LAYOUT>>>

## Conventions
<<<CONVENTIONS>>>

## Build and test
<<<BUILD_AND_TEST>>>

## Branches and commits
- Branch: `issue/<slug>`.
- Don't run `git push`, `gh pr create`, etc. — workflow ends at "merged locally".
- Commits: imperative single line.

## Pre-commit gate (enforced by `/plumage-implement`)
Each commit must pass: green build (zero warnings), green tests, clean SwiftLint, clean `swift-format` lint. `// swiftlint:disable` requires a one-line justification.

## Coding defaults
- Build as modular, reusable, easily extensible, and clean as possible
- Pick the simplest design that works. Don't pre-build abstractions for needs that aren't real.
- Don't change tooling stacks (build system, test framework, package manager) without explicit ask.
- Comments default to none. Inline comments are justified only for non-obvious *why* (workaround, perf trade-off, surprising behavior) — never restate code, never write owner-less TODOs.
- No doc comments (`///`, `/** */`, docstrings) on types, methods, classes, structs, or properties unless I explicitly ask — even if the signature seems unclear.

## Common pitfalls
<<<PITFALLS>>>