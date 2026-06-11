---
name: plumage-plan
description: This skill should be used when the user runs `/plumage-plan <slug>` or `/plumage-plan <slug> - <prompt>`, or asks to "plan an issue", "scope this feature", "write a spec", or "interview me about issue NNNN". Drives an interactive interview that fills out a Plumage issue's `spec.md` and flips it from `draft` to `approved`. Do NOT use for `chore` or `spike` issues — those skip planning and go straight to `/plumage-implement`.
user-invocable: true
disable-model-invocation: true
---

Plumage-plan is the planning half of Plumage's workflow. It runs in Plan Mode (the orchestrator sets this before invoking) and only touches files under `.claude/issues/<id-padded>-<slug>/`.

## Arguments

The skill accepts three forms:

- `/plumage-plan <slug>` — slug only, no prompt. Works with or without Plumage app.
- `/plumage-plan <slug> - <prompt>` — the first ` - ` (space-hyphen-space) separates the slug from the prompt body. Plumage injects this form automatically when an issue has a `prompt.md`; it also works standalone from the terminal.
- `/plumage-plan <prompt>` — input whose first token is not a valid slug (`^[a-z0-9][a-z0-9-]*$`) is treated entirely as prompt. Derive a slug from the prompt and state the choice in the first interview turn, so the user can correct it before the issue folder is created.

The prompt is optional context the user provides upfront (issue description, requirements, notes). When present, treat it as the starting point for the interview — don't ask questions whose answers are already in the prompt. When absent, begin the interview with the Goal topic as normal.

## Workflow

1. Identify relevant installed plugin skills for this project (see "Step 0").
2. Read project context (PROJECT.md, decisions.md — both sections, notes.md), and check other issues' status via `.claude/skills/plumage-plan/scripts/roadmap.py`.
3. Locate or create the spec.
4. Interview the user one topic at a time, writing each section into the spec as the interview progresses.
5. On confirmation, set frontmatter `status: approved` and stop.

## Step 0: Find and activate matching skills and agents

Identify the task surface — what domains and tooling this issue actually touches — from the spec, the user's request, or the issue description. Then scan installed skills and subagents and invoke every one whose description matches that surface, before any real work begins. The `/plumage-*` slash command doesn't trip plugin auto-routers (Axiom and similar), so the routing is manual.

- Skills via the Skill tool, subagents via the Agent tool.
- Match on description, not name. Invoke when the description covers the task surface; don't invoke speculatively because a name sounds related.
- Re-scan when work reveals a domain that wasn't obvious at the start.

If nothing matches or no relevant plugin is installed, continue — the scan happens regardless, the activation is what's conditional.

## Read project context

Before the interview starts, read whichever of these files have content:

- `.claude/docs/PROJECT.md` — goals stated here filter the issue's scope.
- `.claude/docs/decisions.md` — both the **Did** section (past technical choices) and the **Won't (and why)** section (deliberately-rejected directions). A "we won't do X" entry from six months ago binds as strongly as a "we did Y". If the user's proposal conflicts with either, surface the conflict *during* the interview, not at the end.
- `.claude/docs/notes.md` — informal observations; library quirks, related work.

If any file is empty or missing, skip and continue. The cross-check is the point, not file-completeness.

Then run `.claude/skills/plumage-plan/scripts/roadmap.py` (if it exists) to get a one-screen view of other issues' status and progress. If a proposed issue overlaps with anything `in-progress` or `waiting-for-review`, surface it during the Goal or Scope topic — duplicate work and merge conflicts are cheaper to prevent than to untangle.

## Locate or create the spec

1. Look for `.claude/issues/*-<slug>/spec.md` (any padding).
2. If found with `status: approved` or later → stop. The issue is past planning. Offer to re-open by resetting status to `draft`, but only proceed with explicit user confirmation.
3. If not found → create it via `scripts/next-issue-id.sh <slug>`. The script allocates the next free ID across active + archive, handles padding from the project's `*.plumage` bundle's `config.json`, and creates the folder and `spec.md` from `.claude/issues/_TEMPLATE.md` with substitutions filled in. If the script exits non-zero, stop and report — do not allocate by hand.

From here the skill makes no distinction between "spec was pre-created" and "spec was just created by the script". In both cases: read whatever frontmatter and body content is already there, run the full interview, and write each section into the spec as you go. Whether Plumage's UI bootstrapped the issue, an earlier `/plumage-plan` left a partial draft, or the script just allocated the ID — same workflow, same outcome.

## Conduct the interview

Load `references/interview-rubric.md` for the eight topics, their order, and the pushback patterns. The rubric explains *why* each pushback exists — use the reasoning to handle cases the rubric does not spell out.

Engage one topic at a time. After each user reply, restate the understanding in one line, then ask the next question. Do not dump the whole list at once. Write each section into the spec as the interview goes — the spec is the running record, not an end-of-interview dump.

ultrathink before formulating the first interview question. The first turn sets the framing for everything that follows; getting the goal and scope sharp early saves rework later.

## Finalize

When the user confirms the spec is complete:

1. Set frontmatter `status: approved` and `updated:` to now (ISO 8601 UTC, e.g. `2026-05-11T12:00:00Z`).
2. Verify `id`, `title`, `type`, `status`, `created`, `branch` are all populated. A missing required field parks the issue in `invalid` state.
3. Print one line: `Spec approved. Run /plumage-implement <id-padded>-<slug> when ready.`

The Plan Mode subprocess exits on its own once the spec reaches `approved`. Do not exit it explicitly.

## When to stop and ask

Stop and ask under any of these conditions:

- Goal or scope answer is vague ("make it better", "good UX") — ask for a concrete example before writing anything into the spec.
- The proposed approach conflicts with `PROJECT.md` or a `decisions.md` entry — surface the conflict, let the user choose: change the issue, change the doc, or split.
- The user offers two implementation shapes ("we could do X or Y") — ask for the commitment; the spec records one approach.
- A task mixes refactor + feature — ask to split.
- A "Done when" criterion depends on subjective judgment that can't be checked — rewrite it.
- The task list grows past ~15 — propose splitting the issue and stop.

## What this skill does NOT do

- Does not create branches, commits, or any code — that is `/plumage-implement`.
- Does not push, merge, or open PRs.
- Does not move the status past `approved`.
- Does not edit anything outside the issue's own folder.
- Does not run outside Plan Mode — if Plan Mode is not active when this skill starts, stop and tell the user.
