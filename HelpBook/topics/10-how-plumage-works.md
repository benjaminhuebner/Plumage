---
id: how-plumage-works
swift: howPlumageWorks
title: How Plumage Works
icon: info.circle
section: The App
---
# How Plumage Works

Plumage is a native macOS front end for Claude Code workflows: issues on a Kanban board, an embedded agent session, an integrated editor and a local PR view.

## The bundled setup is optional

Plumage ships with a complete setup: a plan/implement/review workflow, project templates, hooks and skills. None of it is mandatory. Everything under `.claude/` is plain files scaffolded from templates you control. The workflow buttons run commands you can edit per project. Use the bundled workflow as it is or replace any part of it with your own. The "Bundled Defaults" section covers what ships in the box; everything else in this help, including the template system, describes the app itself and applies no matter how you set things up.

## Files are the source of truth

Plumage stores nothing in a database. Everything lives in plain files inside your project:

- `.claude/` holds issues, docs, hooks and skills. These are the same files Claude Code reads.
- `<name>.plumage` is a bundle in your project folder with Plumage's own metadata: project configuration, run state and session bookkeeping.

Plain-file state survives crashes and restarts. Git versions it like source code. When something looks wrong, any text editor will do.

## Local by design

The workflow ends at "merged locally". Plumage never pushes on its own and never opens pull requests. The PR view is a local artifact rendered from the issue's `pr.md`. With a connected GitHub account, pushing and pulling are still manual actions.

## Claude runs as a subprocess

All Claude interaction goes through the `claude` command-line tool installed on your Mac. It is the same Claude Code you would run in a terminal, with the same login. Plumage never calls the Anthropic API directly, so a Claude Pro or Max subscription works the same way it does in a terminal session.
