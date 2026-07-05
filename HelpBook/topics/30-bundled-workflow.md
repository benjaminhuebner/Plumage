---
id: bundled-workflow
swift: bundledWorkflow
title: The Bundled Workflow
icon: checklist
section: Bundled Defaults
---
# The Bundled Workflow

Plumage ships a ready-made issue workflow: plan a spec, implement it task by task, review the result. Every piece of it can be reconfigured or replaced.

## The three buttons

The Plan, Implement and Review buttons on an issue start a Claude session with a configurable command. Out of the box they run the bundled skills:

| Button | Default command | Permission mode |
| --- | --- | --- |
| Plan | `/plumage-plan` | Plan Mode |
| Implement | `/plumage-implement` | Accept Edits |
| Review | `/plumage-review` | Default |

Project settings let you edit each command (with `<slug>`, `<prompt>` and `<spec>` placeholders and per-issue-type `#if` branches), change its permission mode and pick a model and effort per workflow. The buttons launch whatever workflow you point them at.

## What the bundled Implement does

The bundled implement skill works through the spec task by task on the issue's own branch, committing a checkpoint after each task. Every commit must pass a pre-commit gate. In the bundled Swift setup that means a warning-free build, green tests, clean SwiftLint and clean swift-format. The gate script is a file in your project and evolves with your stack.

The skill does not merge, push or archive. Those remain your explicit actions.

## Branches

Each issue works on its own branch, named `issue/<slug>` by default. The prefix and the default target branch are configurable in the project's `config.json` (`git.branchPrefix`, `git.defaultBranch`).

## Parallel runs

Builds and tests run strictly serially across all worktrees; a "waiting for gate lock" line in a run is normal queueing rather than an error. Two implement runs can execute in parallel only in separate git worktrees. Starting a second run in the same checkout queues it first-in-first-out behind the active one.

Run state lives in the `.plumage` bundle (`runs/`), so an interrupted run can be resumed after a crash or restart.

## Make it yours

The skills behind the default commands are plain files in your project's `.claude/skills/`. Edit them there or override the templates that scaffold them to change what future projects start with (see Templates & Scaffolding).
