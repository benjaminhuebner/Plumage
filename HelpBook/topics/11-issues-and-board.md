---
id: issues-and-board
swift: issuesAndBoard
title: Issues & the Board
icon: rectangle.split.3x1
section: The App
---
# Issues & the Board

Issues live in `.claude/issues/<id>-<slug>/spec.md`. The spec's frontmatter is the source of truth; the board is a view of those files.

## Statuses and columns

An issue is in one of six statuses: `draft`, `approved`, `in-progress`, `waiting-for-review`, `done` or `blocked`.

The board shows four columns:

| Column | Statuses |
| --- | --- |
| Todo | `draft`, `approved`, `blocked` |
| In Progress | `in-progress` |
| Waiting for Review | `waiting-for-review` |
| Done | `done` |

Draft, approved and blocked issues share the Todo column; look at the card's status badge to tell them apart.

## Who moves an issue

The `status:` field is ordinary spec frontmatter. Like the rest of the file, it belongs to you. With the bundled workflow the skills manage it: Plan flips `draft` to `approved`, Implement moves through `in-progress` to `waiting-for-review` and the app's Merge action flips a merged issue to `done`. If you run your own workflow, edit `status:` however you like. The board follows the file.

## Issue types

Each issue has a type, configurable in Settings > Issue Types. A type's "draft blocks implement" flag decides whether an issue must be planned before the Implement button enables. By default only features require planning; chores, spikes and refactors can go straight from draft to Implement.
