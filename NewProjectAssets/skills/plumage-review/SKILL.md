---
name: plumage-review
description: This skill should be used when the user runs `/plumage-review <slug>` or asks to "review the PR", "check this before merge", "go over issue NNNN", or "tell me if this is mergeable". Reads an issue's spec, PR.md, and the cumulative diff against the default branch, cross-checks against PROJECT.md and decisions.md, and appends a structured review section to PR.md ending with one of three recommendations (Accept / Reject / Discuss). Do NOT use to merge, reject the issue, or move status — those are user actions via Plumage's UI buttons.
user-invocable: true
disable-model-invocation: true
---

Plumage-review takes an issue that is `waiting-for-review` and produces a structured review. Read the spec, the PR.md, and the diff. Cross-check against project docs. Append the review to PR.md. End with a recommendation. The skill never modifies spec status — that is the user's decision via Plumage's UI buttons.

## Standalone usage

This skill works without the Plumage app: invoke `/plumage-review <slug>` directly from a `claude` REPL session in the project root. The slug is the folder name under `.claude/issues/` (e.g. `00051-general-improvements`). The issue branch must exist locally and `PR.md` must be present — those are written by `/plumage-implement`.

## Step 0: Find and activate matching skills and agents

Identify the task surface — what domains and tooling this issue actually touches — from the spec, the user's request, or the issue description. Then scan installed skills and subagents and invoke every one whose description matches that surface, before any real work begins. The `/plumage-*` slash command doesn't trip plugin auto-routers (Axiom and similar), so the routing is manual. This project's primary domains and tooling are: <<<SKILL_KEYWORDS>>> — use these as the starting descriptions to match installed skills and agents against.

- Skills via the Skill tool, subagents via the Task tool.
- Match on description, not name. Invoke when the description covers the task surface; don't invoke speculatively because a name sounds related.
- Re-scan when work reveals a domain that wasn't obvious at the start.

If nothing matches or no relevant plugin is installed, continue — the scan happens regardless, the activation is what's conditional.

## Preconditions

Read `.claude/issues/<id-padded>-<slug>/spec.md` and dispatch on frontmatter `status`:

| Status | Action |
|---|---|
| `waiting-for-review` | Proceed. |
| `in-progress` | Stop. Tell the user to wait until `/plumage-implement` finishes. |
| `approved` or `draft` | Stop. Nothing to review yet — no commits on the issue branch. |
| `done` | Stop. Already merged. Review is for pre-merge inspection. |

Also confirm: the issue branch `issue/<slug>` exists and `PR.md` exists in the issue folder. If either is missing, stop and report — the issue is in an inconsistent state.

## Read project context

Before forming any finding, read whichever of these files have content:

- `.claude/docs/PROJECT.md` — what the project is and is not. A diff implementing something out-of-scope is reviewable even if the diff itself is clean.
- `.claude/docs/decisions.md` — both **Did** and **Won't (and why)**. The cross-check matters: a diff that revives a rejected direction is blocking, even if the diff is technically good.
- `.claude/docs/notes.md` — library quirks, perf notes, known traps. A diff that hits a known trap deserves a note.

Optionally run `.plumage/scripts/roadmap.py` to see whether other issues are in flight. Helpful when the diff touches code that may interact with an `in-progress` issue elsewhere — surface that as a Note so the user can think about merge order.

## Read the PR

Read in this order:

1. **`spec.md`** — what the issue was supposed to do. Goal, scope, technical approach, tasks, done-when.
2. **`PR.md`** — what `/plumage-implement` says it did. Summary, diff stats, commit list, how-to-test, notes.
3. **The diff:** `git diff <defaultBranch>...issue/<slug>` (three-dot, against merge-base). Read `git.defaultBranch` from `.plumage/config.json` (default `main`). If the diff is large (>2000 lines), run `git diff --stat <defaultBranch>...issue/<slug>` first to map the surface, then read full diffs of the most-changed files plus a sample of the rest. Note in the review which files were read fully and which were sampled.
4. **The commits:** `git log <defaultBranch>..issue/<slug> --oneline` to see the progression. Then `git show <hash>` on any commit whose message looks suspicious (catch-all message, big diff for small message, etc.).

## Conduct the review

Load `references/review-rubric.md` for the seven axes, what each one looks for, and the pushback rules. The rubric is the canonical list.

ultrathink before forming the first finding. The first thing flagged sets the tone of the review; getting it sharp avoids burying the real issues under nitpicks.

For each axis, decide: nothing to say / minor observation / blocking concern. Do not manufacture findings to look thorough. A clean axis gets one line ("No concerns.") and the review moves on. Pushback discipline matters more here than during implementation — a review that nods at everything is worse than no review.

Cross-checks that override comfort:

- Diff conflicts with a `decisions.md` **Did** or **Won't** entry → blocking finding.
- Diff adds tests but skips an obvious failure mode named in the spec's edge cases → finding.
- Diff touches files outside what the spec's "Technical approach" said → finding (scope creep is reviewable, even if the result is good).
- `PR.md`'s "How to test" steps do not actually exercise the spec's "Done when" criteria → finding.

## Write the review section

Append to `PR.md` a section that starts with a header line containing today's date in ISO 8601 form, e.g. `## Review (2026-05-24)`.

Inside the section, two parts in this order:

**Findings.** For each rubric axis, one bullet:

- `**<Axis name>** — <one or two sentences>`
- Use `**Blocking:** <finding>` to flag anything that should stop the merge.
- Use `**Question:** <thing the spec does not answer>` for items the user needs to clarify.
- Use `**Note:** <observation>` for things that are not blocking but worth recording.

**Recommendation.** A single bold line. One of:

- `**Recommendation: Accept** — <one-sentence summary>`
- `**Recommendation: Discuss** — <one-sentence summary of what needs a decision>`

`Discuss` covers everything that is not green-light: spec needs revision, approach needs rework, or the diff itself has substantive problems. Use `**Blocking:** ...` findings in the body to flag specific issues that must be resolved before merge.

## Record what was learned

If the review surfaces a non-obvious technical pattern worth keeping for next time — a library quirk, a perf finding, an architectural tension the diff revealed — add one line to `.claude/docs/notes.md`. Do not pad it with restatements of the review.

Do not write to `decisions.md` from the review. Decisions are made by the user, not by review. If the review concludes "this approach should have been X instead", and the user agrees, the *user* writes the decisions entry; the review just records the observation.

## Finish

1. Print the recommendation line a second time on its own, so a UI parser can pick it up from terminal output.
2. Stop. Do not change spec status. Do not run the merge. Do not update any other file.

## When to stop and ask

Stop and ask under any of these conditions:

- Spec status is not `waiting-for-review` (see Preconditions).
- `PR.md` is missing or the issue branch does not exist.
- The diff is empty (`git diff <defaultBranch>...issue/<slug>` produces nothing) — something is wrong with the branch state.
- A finding requires reading code outside the project root.
- Whether something is blocking or stylistic is genuinely unclear — ask the user once, then proceed with their framing.
- The spec and the diff describe two different features — stop the review until the user clarifies which one is correct.

## What this skill does NOT do

- Does not change spec status — Accept/Reject are user actions via Plumage's UI buttons.
- Does not merge, push, or open a remote PR.
- Does not fix the issues it finds — review is diagnosis; fixes go into a follow-up `/plumage-implement` run or a new issue.
- Does not update `decisions.md` — only the user does that.
- Does not rewrite history, squash, or rebase.
- Does not run the pre-commit gate again — `/plumage-implement` already did at the end of its run.
- Does not auto-suggest improvements outside the rubric — manufactured findings dilute the real ones.
