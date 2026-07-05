---
name: plumage-plan
description: This skill should be used when the user runs `/plumage-plan <slug>` or `/plumage-plan <slug> - <prompt>`, or asks to "plan an issue", "scope this feature", "write a spec", or "interview me about issue NNNN". Drives an interactive interview that fills out a Plumage issue's `spec.md` and flips it from `draft` to `approved`. Do NOT use for issue types that skip planning (their "draft blocks implement" flag is off in Plumage's Settings → Issue Types; default: `chore`, `spike`, `refactor`) — those go straight to `/plumage-implement`.
argument-hint: "[slug] - [prompt]"
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

## Step 0: Find and activate matching skills and agents

Identify the task surface — the domains and tooling this issue touches — from the spec, the request, or the issue description. Then invoke every installed skill (Skill tool) and subagent (Agent tool) whose *description* matches that surface, before real work begins; the `/plumage-*` slash command doesn't trip plugin auto-routers (Axiom and similar), so this routing is manual. Match on description, not name; re-scan when work reveals a new domain. No match → continue.

## Read project context

The cross-check against project docs is what makes the interview more than a form-filler — but the docs are large, and this session's context belongs to the interview. Gather the context like this:

- **Delegate the doc sweep to an Explore subagent** and keep only its digest. Give it the issue's topic (slug, prompt, any known scope) and have it report: PROJECT.md scope conflicts, every `decisions.md` **Did** or **Won't** entry that touches the topic (`decisions-archive.md` holds rotated older entries — it binds equally, have the subagent grep it too), and relevant `notes.md` quirks. A "we won't do X" entry binds as strongly as a "we did Y" — if the user's proposal conflicts with either, surface the conflict *during* the interview, not at the end.
- Run `.claude/skills/plumage-plan/scripts/roadmap.py` directly (one screen) for other issues' status. If the proposed issue overlaps with anything `in-progress` or `waiting-for-review`, surface it during the Goal or Scope topic — duplicate work and merge conflicts are cheaper to prevent than to untangle.

If a doc is empty or missing, skip it — the cross-check is the point, not file-completeness.

## Locate or create the spec

1. Look for `.claude/issues/*-<slug>/spec.md` (any padding).
2. If found with `status: approved` or later → stop. The issue is past planning. Offer to re-open by resetting status to `draft`, but only proceed with explicit user confirmation.
3. If not found → create it via `.claude/skills/plumage-plan/scripts/next-issue-id.sh <slug>`. The script allocates the next free ID across active + archive, handles padding, and creates the folder and `spec.md` from `.claude/issues/_TEMPLATE.md`. If the script exits non-zero, stop and report — do not allocate by hand.

The template scaffolds the eight sections with an HTML-comment hint each; **replace each hint with real content** as the interview fills that section — no hint comment survives into an approved spec. Whether Plumage's UI bootstrapped the issue, an earlier `/plumage-plan` left a partial draft, or the script just allocated the ID: same workflow — read what's already there, run the full interview, write each section as you go.

## Conduct the interview

Load `references/interview-rubric.md` for the eight topics, their order, and the pushback patterns. The rubric explains *why* each pushback exists — use the reasoning to handle cases the rubric does not spell out.

Engage one topic at a time. After each user reply, restate the understanding in one line, then ask the next question. Do not dump the whole list at once. Where a topic reduces to a discrete choice — committing to one of two implementation shapes, picking which edge cases matter, choosing what falls out of scope — use the AskUserQuestion tool with concrete options instead of an open question; keep free-form chat for the genuinely open topics (Goal, behavior descriptions). Write each section into the spec as the interview goes — the spec is the running record, not an end-of-interview dump; if the session crashes, the partial spec is the resume point.

ultrathink before formulating the first interview question. The first turn sets the framing for everything that follows; getting the goal and scope sharp early saves rework later.

## Finalize

When the user confirms the spec is complete:

1. Verify no template hint comments remain and `id`, `title`, `type`, `status`, `created`, `branch` are all populated (a missing required field parks the issue in `invalid` state).
2. Set frontmatter `status: approved` and `updated:` to now (ISO 8601 UTC, e.g. `2026-05-11T12:00:00Z`).
3. Print one line: `Spec approved. Run /plumage-implement <id-padded>-<slug> when ready.`

The Plan Mode subprocess exits on its own once the spec reaches `approved` (a PostToolUse hook stops the turn). Do not exit it explicitly.

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
