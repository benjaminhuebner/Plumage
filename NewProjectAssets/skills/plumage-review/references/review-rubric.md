# Review rubric

This reference is loaded by `/plumage-review` when it is time to form findings. Seven axes in fixed order. For each axis, decide: nothing to say / minor observation / blocking concern. Write findings into the PR.md `## Review (<date>)` section as the review progresses.

The rationale matters more than the rigid order: a review that follows the letter of the rubric but produces a checklist the user cannot act on has failed. Use the *why* to handle cases this rubric does not spell out.

## The seven axes

### 1. Spec adherence — does the diff implement what the spec said it would

Cross-check the diff against the spec's "Technical approach", "Tasks", and "Done when".

- Did every task in the spec produce a commit?
- Did the diff touch files outside the spec's "Technical approach"? Scope creep is reviewable even if the extra changes are good — surface it.
- Are the "Done when" criteria actually exercised by the tests in the diff, or only claimed in PR.md?

**Pushback:** "Looks like the spec" is not enough. The reviewer's job is to verify, not to nod. If a spec task is "Add validation for empty input" and the diff has no test that asserts the empty-input case, that is a finding — even if validation code exists.

**Why:** Spec adherence is the contract. A diff that ships something *different* from the spec — even something better — is a sign that planning and implementation drifted, and the user needs to know whether to update the spec or roll the diff back.

### 2. Cross-doc consistency — does the diff respect PROJECT.md, decisions.md, notes.md

Read the project docs *before* judging the diff. Then ask:

- Does the diff conflict with a `decisions.md` **Did** entry? (e.g., decisions says "SwiftPM only", diff adds a CocoaPods config → blocking)
- Does the diff revive a direction `decisions.md` **Won't** explicitly rejected? (e.g., Won't says "no multi-window", diff adds a window manager → blocking)
- Does the diff implement something `PROJECT.md` says is out of scope?
- Are there `notes.md` entries that should have informed the implementation but apparently did not? (e.g., "FileManager is not Sendable", diff uses `let fileManager: FileManager`)

**Pushback:** If the diff conflicts with a decision, surface it as blocking, even if the diff is otherwise excellent. The user has two ways out: update the doc (decisions can be superseded) or update the diff. The review's job is to put the choice in front of the user, not to choose for them.

**Why:** decisions.md is append-only and binding. A diff that silently overrides it without a superseding entry is technical debt with a fuse on it.

### 3. Test coverage — do the tests exercise what matters

Look at the new and changed test files, and at what they actually assert.

- Is each new behavior covered by at least one test?
- Are the edge cases the spec named actually tested?
- Are the tests assertive, or do they just exercise code without checking outcomes? ("Test runs without crashing" is not a test.)
- Did any tests get deleted or weakened, and is that justified by the diff?

**Pushback:** A test that calls the function and does not assert on its return value is not testing — flag it. A test named `testHandlesEdgeCases` that has no edge-case assertions is worse than no test, because it gives false confidence.

**Why:** Coverage is not a number — it is whether the test would *fail* if the behavior broke. A test that passes whether or not the implementation is correct does not cover anything.

### 4. Build hygiene — what the gate would catch, plus what it would not

The pre-commit gate already ran at the end of `/plumage-implement` — its result is in the final commit's state. The reviewer's job is *what the gate does not catch*:

- Warnings silenced with `// swiftlint:disable <rule>` — does each have a one-line justification? Is the justification convincing?
- New uses of `@unchecked Sendable` or `@preconcurrency` — does each have a comment and a `notes.md` entry, per the convention?
- New `TODO`/`FIXME` comments without an owner or issue reference.

**Pushback:** A justification of "needed for this to compile" is not a justification — push for the actual reason. "Needed because `ProcessRunning` is a Sendable struct with a closure property" is one.

**Why:** Static checks have known coverage gaps. Review is the human layer over them.

### 5. Surprise budget — anything unexpected for a future reader

Read the diff as if opening it in three months with no context. Flag:

- Renames or moves that are not justified by the spec.
- Files deleted without explanation in PR.md or commit messages.
- New dependencies (libraries, MCPs, scripts) that the spec did not list.
- Patterns that contradict the project's existing style without a `decisions.md` entry to mark the change.

**Pushback:** "Just refactored while I was in there" is the most common cause of unmerged PRs becoming merge-conflict storms a week later. Flag the refactor as a `Note` even if it is good — that flags it for a future `notes.md` entry, and discourages drift in the next issue.

**Why:** Surprises in a diff are technical debt with a multiplier — each surprise costs the *next* reader, not the author.

### 6. Risk and reversibility — what would it cost to roll this back

For each significant change in the diff:

- Schema migrations or storage-format changes — are they reversible? Did the diff write the down-path?
- Public API changes that downstream code depends on — are they additive (safe) or breaking (need a migration plan)?
- Changes to error-handling defaults (e.g., switching from throw to silent return) — are they intentional and tested?
- Changes that affect data on disk (config formats, cache layouts, file locations) — does the diff handle the migration of existing data?

**Pushback:** "We'll fix it forward if it breaks" is not a strategy for anything that touches user data on disk. For changes that *do* touch persistent state, ask whether `decisions.md` or a migration log records the schema bump.

**Why:** Reversibility is rarely planned; it is discovered when needed. Review is the cheapest place to spot the irreversible move.

### 7. PR.md quality — can a reviewer (or future-you) actually use it

Look at PR.md as a standalone document:

- Does the summary describe the *result*, not restate the spec?
- Are the "How to test" steps reproducible from a fresh `git checkout`, or do they assume hidden state?
- Are the listed commits accurate? (`git log` and PR.md should agree.)
- Is anything noted in "Notes" that was not already in `decisions.md` or `notes.md` — and should it be?

**Pushback:** A PR.md that says "Implemented as per spec" with no further detail is not a PR.md, it is a placeholder. Push for the result.

**Why:** PR.md persists as the record of *what shipped*. Once the spec is closed and the branch is merged, PR.md is what someone will read.

## Review hygiene

- One axis at a time. Form findings before moving on. Do not write the whole review at once.
- Severity discipline: most axes will be "no concerns" on a well-implemented issue. That is fine and accurate. Manufacturing concerns to look thorough is worse than missing a real one.
- The review records observations; the user decides. Do not write "this should be X" as if the call is final — write "this is X; the spec said Y; clarify which is intended" and let the user resolve.
- The review is to the *user*, not to the implementer. Write findings the user can act on, not feedback the implementer should have caught.
