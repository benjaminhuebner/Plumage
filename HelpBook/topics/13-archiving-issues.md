---
id: archiving-issues
swift: archivingIssues
title: Archiving Issues
icon: archivebox
section: The App
---
# Archiving Issues

Archiving moves a finished issue off the board without deleting anything.

## How it works

Archiving moves the issue's whole folder from `.claude/issues/<id>-<slug>/` to `.claude/issues/archive/<id>-<slug>/`. Nothing is rewritten; spec, docs and PR file travel as-is. If a folder with the same name already exists in the archive, a numeric suffix is appended.

## The Archive view

The Archive entry in the sidebar lists archived issues read-only. Unarchive an issue from its context menu and the folder moves straight back to `.claude/issues/`, where the issue reappears on the board.

Archiving is always a manual action. Finishing or merging an issue never archives it automatically.
